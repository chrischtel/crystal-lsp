#!/usr/bin/env crystal

require "./src/lsp"
require "./examples/windows_compatible_controller"

# Simple test runner for our LSP server
puts "Starting Crystal LSP Server (Windows Compatible)"
puts "Crystal version: #{Crystal::VERSION}"
puts "Platform: #{LSP::Platform.windows? ? "Windows" : "Unix"}"

# Create our controller
controller = WindowsCompatibleController.new

# Create and start the server
server = LSP::Server.new(STDIN, STDOUT)

# Set up logging to stderr so it doesn't interfere with LSP communication
Log.setup do |config|
  config.bind "*", :info, Log::IOBackend.new(STDERR)
end

puts "LSP Server starting... (listening on STDIN/STDOUT)"
platform_info = {
  "os" => LSP::Platform.windows? ? "Windows" : "Unix",
  "crystal_version" => Crystal::VERSION,
  "line_ending" => LSP::Platform.line_ending.inspect
}
puts "Platform info: #{platform_info}"

# Start the server with our controller
begin
  server.start(controller)
rescue ex
  STDERR.puts "Server error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n")
  exit 1
end
