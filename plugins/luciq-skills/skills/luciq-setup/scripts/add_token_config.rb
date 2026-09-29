#!/usr/bin/env ruby
# frozen_string_literal: true

# Keeps the Luciq app token out of source control on iOS:
#
#   <xcconfig>  (gitignored)   LUCIQ_APP_TOKEN = <token>
#        │  base configuration of every build config of the target
#        ▼                     (or #include? from the existing base xcconfig)
#   Info.plist                 LuciqAppToken = $(LUCIQ_APP_TOKEN)
#        │  a real file — INFOPLIST_KEY_<Custom> build settings are silently dropped
#        ▼
#   Bundle.main.object(forInfoDictionaryKey: "LuciqAppToken")
#
# Creates the xcconfig with an empty value (fill it in afterwards), a committed
# <xcconfig>.example, the .gitignore entry, the Info.plist key, and the build
# settings. Never takes the token itself. Idempotent.
#
# Usage:
#   ruby add_token_config.rb --project App.xcodeproj --target App \
#     [--xcconfig Config/Luciq.xcconfig] [--plist Config/Info.plist] \
#     [--key LuciqAppToken] [--var LUCIQ_APP_TOKEN]

require 'optparse'
require 'fileutils'
require 'pathname'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

opts = {
  xcconfig: 'Config/Luciq.xcconfig',
  plist: 'Config/Info.plist',
  key: 'LuciqAppToken',
  var: 'LUCIQ_APP_TOKEN',
  allow_xcode_open: false
}
OptionParser.new do |o|
  o.on('--project PATH') { |v| opts[:project] = v }
  o.on('--target NAME') { |v| opts[:target] = v }
  o.on('--xcconfig PATH', 'relative to the project directory') { |v| opts[:xcconfig] = v }
  o.on('--plist PATH', 'used only when the target has no Info.plist file yet') { |v| opts[:plist] = v }
  o.on('--key NAME') { |v| opts[:key] = v }
  o.on('--var NAME') { |v| opts[:var] = v }
  o.on('--allow-xcode-open') { opts[:allow_xcode_open] = true }
end.parse!

missing = %i[project target].reject { |k| opts[k] }
abort("error: missing --#{missing.join(', --')}") unless missing.empty?

begin
  require 'xcodeproj'
rescue LoadError
  abort('error: the xcodeproj gem is not installed. Run: gem install xcodeproj')
end

if !opts[:allow_xcode_open] && system('pgrep -xq Xcode')
  abort('error: Xcode is running. Quit Xcode, re-run this script, then reopen the project.')
end

project = Xcodeproj::Project.open(opts[:project])
src_root = Pathname.new(File.dirname(File.expand_path(opts[:project])))
target = project.native_targets.find { |t| t.name == opts[:target] }
abort("error: target '#{opts[:target]}' not found. Targets: #{project.native_targets.map(&:name).join(', ')}") unless target

changed = false
xcconfig_abs = src_root.join(opts[:xcconfig])

# 1. The gitignored xcconfig (value left empty) and a committed example.
unless xcconfig_abs.exist?
  FileUtils.mkdir_p(xcconfig_abs.dirname)
  File.write(xcconfig_abs, "// Not committed. Holds the Luciq app token for local builds.\n#{opts[:var]} =\n")
  puts "+ created #{opts[:xcconfig]} (fill in #{opts[:var]})"
end
example = Pathname.new("#{xcconfig_abs}.example")
unless example.exist?
  File.write(example, "// Copy to #{xcconfig_abs.basename} and fill in. CI writes it from a secret.\n#{opts[:var]} =\n")
  puts "+ created #{opts[:xcconfig]}.example"
end

gitignore = src_root.join('.gitignore')
repo_root = `git -C "#{src_root}" rev-parse --show-toplevel 2>/dev/null`.strip
gitignore = Pathname.new(repo_root).join('.gitignore') unless repo_root.empty?
ignore_line = xcconfig_abs.relative_path_from(gitignore.dirname).to_s
existing = gitignore.exist? ? File.read(gitignore) : ''
unless existing.lines.map(&:strip).include?(ignore_line)
  File.write(gitignore, existing + (existing.empty? || existing.end_with?("\n") ? '' : "\n") + "#{ignore_line}\n")
  puts "+ .gitignore: #{ignore_line}"
end

# 2. Base configuration: set it, or #include? it from the one already there.
xcconfig_ref = project.files.find { |f| f.real_path == xcconfig_abs }
target.build_configurations.each do |config|
  base = config.base_configuration_reference
  if base.nil?
    xcconfig_ref ||= project.main_group.new_file(xcconfig_abs.to_s)
    config.base_configuration_reference = xcconfig_ref
    changed = true
    puts "+ #{config.name}: base configuration = #{opts[:xcconfig]}"
  elsif base.real_path != xcconfig_abs
    include_path = xcconfig_abs.relative_path_from(base.real_path.dirname).to_s
    line = %(#include? "#{include_path}")
    content = File.read(base.real_path)
    next if content.include?(line)

    File.write(base.real_path, "#{line}\n#{content}")
    puts "+ #{config.name}: #{line} added to #{base.real_path.relative_path_from(src_root)}"
  end
end

# 3. A real Info.plist carrying the key.
plist_setting = target.build_configurations.map { |c| c.build_settings['INFOPLIST_FILE'] }.compact.first
plist_rel = plist_setting || opts[:plist]
plist_abs = src_root.join(plist_rel.gsub('$(SRCROOT)/', ''))
unless plist_abs.exist?
  FileUtils.mkdir_p(plist_abs.dirname)
  Xcodeproj::Plist.write_to_path({}, plist_abs.to_s)
  puts "+ created #{plist_rel}"
end
plist = Xcodeproj::Plist.read_from_path(plist_abs.to_s)
unless plist[opts[:key]] == "$(#{opts[:var]})"
  plist[opts[:key]] = "$(#{opts[:var]})"
  Xcodeproj::Plist.write_to_path(plist, plist_abs.to_s)
  puts "+ #{plist_rel}: #{opts[:key]} = $(#{opts[:var]})"
end
unless plist_setting
  target.build_configurations.each { |c| c.build_settings['INFOPLIST_FILE'] = plist_rel }
  changed = true
  puts "+ INFOPLIST_FILE = #{plist_rel} (generated keys still merge in)"
end

if changed
  project.save
  puts "saved #{opts[:project]}"
else
  puts 'project file unchanged'
end
puts "\nNext: put the token in #{opts[:xcconfig]} and read it with " \
     "Bundle.main.object(forInfoDictionaryKey: \"#{opts[:key]}\") as? String"
