#!/usr/bin/env crystal

require "json"
require "process"

# Simple LSP client to test our server
class LSPTestClient
  def initialize(@process : Process)
    @id_counter = 0
  end

  def next_id
    @id_counter += 1
  end

  def send_message(message : Hash)
    content = message.to_json
    header = "Content-Length: #{content.bytesize}\r\n\r\n"

    puts "Sending: #{content}"
    @process.input.print(header)
    @process.input.print(content)
    @process.input.flush
  end

  def send_request(method : String, params = nil)
    message = {
      "jsonrpc" => "2.0",
      "id" => next_id,
      "method" => method,
      "params" => params
    }.compact

    send_message(message)
  end

  def send_notification(method : String, params = nil)
    message = {
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }.compact

    send_message(message)
  end

  def read_response
    # Read Content-Length header
    output = @process.output
    line = output.gets
    return nil unless line

    if line.starts_with?("Content-Length:")
      length = line.split(":")[1].strip.to_i
      # Read the empty line
      output.gets
      # Read the content
      content = output.read_string(length)
      puts "Received: #{content}"
      return JSON.parse(content)
    end

    nil
  end

  def close
    @process.input.close
    @process.wait
  end
end

puts "Starting LSP Test Client"
puts "Launching LSP server..."

# Start our LSP server
process = Process.new(
  "bin/test_lsp_server.exe",
  input: Process::Redirect::Pipe,
  output: Process::Redirect::Pipe,
  error: Process::Redirect::Inherit
)

client = LSPTestClient.new(process)

begin
  # Send initialize request
  puts "\n--- Sending initialize request ---"
  client.send_request("initialize", {
    "processId" => Process.pid,
    "clientInfo" => {
      "name" => "test-client",
      "version" => "1.0.0"
    },
    "rootUri" => "file:///#{Dir.current.gsub("\\", "/")}",
    "capabilities" => {
      "textDocument" => {
        "hover" => {
          "contentFormat" => ["markdown", "plaintext"]
        },
        "completion" => {
          "completionItem" => {
            "snippetSupport" => true
          }
        }
      }
    }
  })

  # Read initialize response
  response = client.read_response
  puts "Initialize response: #{response}"

  # Send initialized notification
  puts "\n--- Sending initialized notification ---"
  client.send_notification("initialized", {} of String => String)

  # Test document operations
  puts "\n--- Testing document operations ---"

  # Open a document
  client.send_notification("textDocument/didOpen", {
    "textDocument" => {
      "uri" => "file:///test.cr",
      "languageId" => "crystal",
      "version" => 1,
      "text" => "# Test Crystal file\nclass MyClass\n  def hello\n    puts \"Hello, Windows!\"\n  end\nend\n"
    }
  })

  # Test hover request
  puts "\n--- Testing hover request ---"
  client.send_request("textDocument/hover", {
    "textDocument" => {
      "uri" => "file:///test.cr"
    },
    "position" => {
      "line" => 1,
      "character" => 6
    }
  })

  # Read hover response
  hover_response = client.read_response
  puts "Hover response: #{hover_response}"

  # Test completion request
  puts "\n--- Testing completion request ---"
  client.send_request("textDocument/completion", {
    "textDocument" => {
      "uri" => "file:///test.cr"
    },
    "position" => {
      "line" => 3,
      "character" => 10
    }
  })

  # Read completion response
  completion_response = client.read_response
  puts "Completion response: #{completion_response}"

  # Change document content
  puts "\n--- Testing document change ---"
  client.send_notification("textDocument/didChange", {
    "textDocument" => {
      "uri" => "file:///test.cr",
      "version" => 2
    },
    "contentChanges" => [{
      "text" => "# Updated Crystal file\nclass MyClass\n  def hello\n    puts \"Hello, Windows World!\"\n  end\nend\n"
    }]
  })

  # Save document
  puts "\n--- Testing document save ---"
  client.send_notification("textDocument/didSave", {
    "textDocument" => {
      "uri" => "file:///test.cr"
    }
  })

  # Close document
  puts "\n--- Testing document close ---"
  client.send_notification("textDocument/didClose", {
    "textDocument" => {
      "uri" => "file:///test.cr"
    }
  })

  # Send shutdown request
  puts "\n--- Sending shutdown request ---"
  client.send_request("shutdown", nil)

  # Read shutdown response
  shutdown_response = client.read_response
  puts "Shutdown response: #{shutdown_response}"

  # Send exit notification
  puts "\n--- Sending exit notification ---"
  client.send_notification("exit", nil)

  puts "\n--- Test completed successfully! ---"

rescue ex
  puts "Error during test: #{ex.message}"
  puts ex.backtrace.join("\n")
ensure
  client.close
end
