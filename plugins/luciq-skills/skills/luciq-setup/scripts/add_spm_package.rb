#!/usr/bin/env ruby
# frozen_string_literal: true

# Wires a remote Swift package product into an .xcodeproj app target, the way
# Xcode's own "Add Package Dependencies…" does — without hand-editing
# project.pbxproj or inventing 24-hex object IDs.
#
# Writes the four objects Xcode writes:
#   XCRemoteSwiftPackageReference   (PBXProject.packageReferences)
#   XCSwiftPackageProductDependency (PBXNativeTarget.packageProductDependencies)
#   PBXBuildFile with productRef    (the target's Frameworks build phase)
#
# Idempotent: re-running with the same URL/product reuses what is there.
#
# Usage:
#   ruby add_spm_package.rb --project App.xcodeproj --target App \
#     --url https://github.com/<org>/<repo> --version 19.0.0 --product <Product>
#
# Requires the xcodeproj gem (>= 1.27.0 for Xcode 16+ projects, objectVersion 77).

require 'optparse'

# Agent shells often run without a UTF-8 locale; the gem then fails to parse
# any project.pbxproj containing non-ASCII bytes.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

opts = { allow_xcode_open: false }
OptionParser.new do |o|
  o.banner = 'Usage: add_spm_package.rb --project P.xcodeproj --target T --url URL --version X.Y.Z --product NAME'
  o.on('--project PATH') { |v| opts[:project] = v }
  o.on('--target NAME') { |v| opts[:target] = v }
  o.on('--url URL') { |v| opts[:url] = v }
  o.on('--version X.Y.Z', 'minimumVersion for upToNextMajorVersion') { |v| opts[:version] = v }
  o.on('--product NAME', 'SPM product name (from the package manifest, not the import name)') { |v| opts[:product] = v }
  o.on('--allow-xcode-open', 'Skip the Xcode-is-running guard') { opts[:allow_xcode_open] = true }
end.parse!

missing = %i[project target url version product].reject { |k| opts[k] }
abort("error: missing --#{missing.join(', --')}") unless missing.empty?

begin
  require 'xcodeproj'
rescue LoadError
  abort('error: the xcodeproj gem is not installed. Run: gem install xcodeproj')
end

# Xcode keeps its own in-memory copy of the project. Editing the file underneath
# it leaves the package referenced but never resolved ("Missing package product").
unless opts[:allow_xcode_open]
  if system('pgrep -xq Xcode')
    abort("error: Xcode is running. Quit Xcode, re-run this script, then reopen the project.\n" \
          '       (Or pass --allow-xcode-open and run File > Packages > Resolve Package Versions in Xcode afterwards.)')
  end
end

begin
  project = Xcodeproj::Project.open(opts[:project])
rescue StandardError => e
  hint = e.message.include?('object version') ? ' Update the gem: gem install xcodeproj (>= 1.27.0 reads Xcode 16+ projects).' : ''
  abort("error: could not open #{opts[:project]}: #{e.message}.#{hint}")
end

target = project.native_targets.find { |t| t.name == opts[:target] }
unless target
  names = project.native_targets.map(&:name).join(', ')
  abort("error: target '#{opts[:target]}' not found. Targets: #{names}")
end

changed = false
normalize = ->(u) { u.to_s.sub(%r{/+\z}, '').sub(/\.git\z/, '').downcase }

root = project.root_object
package_ref = root.package_references.find do |r|
  r.is_a?(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference) &&
    normalize.call(r.repositoryURL) == normalize.call(opts[:url])
end

if package_ref
  puts "= package reference already present: #{package_ref.repositoryURL}"
else
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = opts[:url]
  package_ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => opts[:version] }
  root.package_references << package_ref
  changed = true
  puts "+ package reference: #{opts[:url]} (from #{opts[:version]}, up to next major)"
end

product_dep = target.package_product_dependencies.find do |d|
  d.product_name == opts[:product] && d.package == package_ref
end

if product_dep
  puts "= product '#{opts[:product]}' already a dependency of '#{target.name}'"
else
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = package_ref
  product_dep.product_name = opts[:product]
  target.package_product_dependencies << product_dep
  changed = true
  puts "+ product dependency: #{opts[:product]} -> target #{target.name}"
end

# Without this, the product builds but is never linked into the app.
linked = target.frameworks_build_phase.files.any? { |f| f.product_ref == product_dep }
if linked
  puts "= '#{opts[:product]}' already in the Frameworks build phase"
else
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  target.frameworks_build_phase.files << build_file
  changed = true
  puts "+ linked '#{opts[:product]}' in the Frameworks build phase"
end

if changed
  project.save
  puts "saved #{opts[:project]}"
else
  puts 'nothing to change'
end
