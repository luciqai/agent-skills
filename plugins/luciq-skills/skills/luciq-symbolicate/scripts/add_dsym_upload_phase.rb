#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds an "Upload dSYMs to Luciq" Run Script phase to an .xcodeproj app target
# that works with Xcode's user-script sandboxing (ENABLE_USER_SCRIPT_SANDBOXING,
# on by default for projects created in Xcode 15+).
#
# Under the sandbox a script phase may read only its declared input files and
# write only its declared output files. A hand-written phase that zips
# $DWARF_DSYM_FOLDER_PATH fails with "Sandbox: zip deny(1) file-read-data" and
# breaks every Release build and archive. This phase instead:
#   - declares the dSYM's Info.plist and DWARF binary as inputs, which also
#     orders it after dSYM generation (an undeclared phase can run before it);
#   - declares the zip as its output, in DERIVED_FILE_DIR;
#   - zips only those two files, streamed to stdout, because `zip -r` reads
#     undeclared files and zip's temp file is an undeclared write.
#
# Idempotent: re-running updates the phase with the same name in place.
#
# To test the phase without uploading, build with the setting
# LUCIQ_SKIP_UPLOAD=YES (e.g. `xcodebuild ... LUCIQ_SKIP_UPLOAD=YES build`):
# the sandboxed zip still runs, the upload is skipped.
#
# Usage:
#   ruby add_dsym_upload_phase.rb --project App.xcodeproj --target App \
#     --slug my-app --mode production [--configuration Release ...]
#
# Requires the xcodeproj gem (>= 1.27.0 for Xcode 16+ projects, objectVersion 77).

require 'optparse'

# Agent shells often run without a UTF-8 locale; the gem then fails to parse
# any project.pbxproj containing non-ASCII bytes.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

PHASE_NAME = 'Upload dSYMs to Luciq'
SAFE_VALUE = /\A[A-Za-z0-9._-]+\z/

opts = { configurations: [], allow_xcode_open: false }
OptionParser.new do |o|
  o.banner = 'Usage: add_dsym_upload_phase.rb --project P.xcodeproj --target T --slug SLUG --mode MODE [--configuration NAME ...]'
  o.on('--project PATH') { |v| opts[:project] = v }
  o.on('--target NAME') { |v| opts[:target] = v }
  o.on('--slug SLUG', 'App slug, as `luciq apps list` prints it') { |v| opts[:slug] = v }
  o.on('--mode MODE', 'Mode the build reports to (production, beta, ...)') { |v| opts[:mode] = v }
  o.on('--configuration NAME', 'Build configuration that uploads (repeatable, default Release)') { |v| opts[:configurations] << v }
  o.on('--allow-xcode-open', 'Skip the Xcode-is-running guard') { opts[:allow_xcode_open] = true }
end.parse!

missing = %i[project target slug mode].reject { |k| opts[k] }
abort("error: missing --#{missing.join(', --')}") unless missing.empty?
opts[:configurations] = ['Release'] if opts[:configurations].empty?

# These values are pasted into a shell script; refuse anything that needs quoting.
([opts[:slug], opts[:mode]] + opts[:configurations]).each do |v|
  abort("error: '#{v}' may only contain letters, digits, '.', '_' and '-'") unless v.match?(SAFE_VALUE)
end

begin
  require 'xcodeproj'
rescue LoadError
  abort('error: the xcodeproj gem is not installed. Run: gem install xcodeproj')
end

# Xcode keeps its own in-memory copy of the project and overwrites edits made
# underneath it the next time it saves.
unless opts[:allow_xcode_open]
  if system('pgrep -xq Xcode')
    abort("error: Xcode is running. Quit Xcode, re-run this script, then reopen the project.\n" \
          '       (Or pass --allow-xcode-open if you are sure Xcode will not save over the change.)')
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

dsym = '$(DWARF_DSYM_FOLDER_PATH)/$(DWARF_DSYM_FILE_NAME)'
input_paths = [
  "#{dsym}/Contents/Info.plist",
  "#{dsym}/Contents/Resources/DWARF/$(EXECUTABLE_NAME)"
]
output_paths = ['$(DERIVED_FILE_DIR)/luciq-dsyms.zip']

configuration_case = opts[:configurations].join('|')
shell_script = <<~SH
  # Added by luciq-symbolicate (scripts/add_dsym_upload_phase.rb).
  # Sandbox-safe: reads only the declared inputs, writes only the declared output.
  set -eu
  case "$CONFIGURATION" in #{configuration_case}) ;; *) exit 0 ;; esac
  if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
    echo "warning: DEBUG_INFORMATION_FORMAT is not dwarf-with-dsym for $CONFIGURATION, no dSYM to upload"; exit 0
  fi
  # Xcode runs scripts with a minimal PATH; add the usual CLI install locations.
  export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  if ! command -v luciq >/dev/null 2>&1; then
    echo "warning: luciq CLI not found, skipping symbol upload (brew install luciqai/tap/luciq-cli)"; exit 0
  fi
  if [ -z "${LUCIQ_AUTH_TOKEN:-}" ] && [ ! -f "$HOME/.luciqrc" ]; then
    echo "warning: no Luciq credentials, skipping symbol upload (run: luciq login)"; exit 0
  fi
  DSYM="$DWARF_DSYM_FILE_NAME"
  # Zip only the declared files, streamed: `zip -r` and zip's temp file both fall outside the sandbox.
  (cd "$DWARF_DSYM_FOLDER_PATH" && zip -q - "$DSYM/Contents/Info.plist" "$DSYM/Contents/Resources/DWARF/$EXECUTABLE_NAME") > "$SCRIPT_OUTPUT_FILE_0"
  # Smoke builds pass LUCIQ_SKIP_UPLOAD=YES: everything above runs, nothing is sent.
  if [ "${LUCIQ_SKIP_UPLOAD:-}" = "YES" ]; then
    echo "note: LUCIQ_SKIP_UPLOAD=YES, dSYM zipped to $SCRIPT_OUTPUT_FILE_0, not uploaded"; exit 0
  fi
  luciq upload ios-dsym "$SCRIPT_OUTPUT_FILE_0" --slug #{opts[:slug]} --mode #{opts[:mode]}
SH

# A differently named phase that already uploads would upload twice.
others = target.shell_script_build_phases.select do |p|
  p.name != PHASE_NAME && p.shell_script.to_s.include?('luciq upload')
end
others.each do |p|
  warn "warning: phase '#{p.name}' already runs `luciq upload`. Remove it, or it uploads twice " \
       '(and fails under ENABLE_USER_SCRIPT_SANDBOXING if it zips the dSYM folder).'
end

phase = target.shell_script_build_phases.find { |p| p.name == PHASE_NAME }
if phase
  unchanged = phase.shell_script == shell_script &&
              phase.input_paths == input_paths &&
              phase.output_paths == output_paths
  if unchanged
    puts "= '#{PHASE_NAME}' already up to date in '#{target.name}'"
    puts 'nothing to change'
    exit 0
  end
  puts "~ updating '#{PHASE_NAME}' in '#{target.name}'"
else
  phase = target.new_shell_script_build_phase(PHASE_NAME)
  puts "+ added '#{PHASE_NAME}' to '#{target.name}'"
end

phase.shell_path = '/bin/sh'
phase.shell_script = shell_script
phase.input_paths = input_paths
phase.output_paths = output_paths
phase.show_env_vars_in_log = '0'

# Keep it last so it never sits between phases that build the app.
target.build_phases.delete(phase)
target.build_phases << phase

project.save
puts "  runs for: #{opts[:configurations].join(', ')} -> --slug #{opts[:slug]} --mode #{opts[:mode]}"
puts "saved #{opts[:project]}"
