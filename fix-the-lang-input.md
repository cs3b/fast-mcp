Perfect — here’s the AI coding agent prompt to improve your stdio_transport.rb MCP server’s STDIO layer handling of large JSON-RPC inputs, formatted in Markdown:

🛠️ Prompt: Improve STDIO Transport Layer for Ruby MCP Server

📝 Description

You are a coding assistant helping to improve a Ruby-based implementation of the Model Context Protocol (MCP) server, specifically its STDIO transport layer as defined in the MCP 2024-11-05 specification.

The server currently uses STDIO to read JSON-RPC requests, one per line. However, when a large request is sent (e.g. a long prompt with an embedded transcript), it fails to process the message correctly — either due to partial reads or incorrect string splitting.

🎯 Goals

Improve stdio_transport.rb to:
	1.	✅ Fully support large single-line JSON inputs (even those thousands of characters long).
	2.	✅ Respect the line-delimited JSON-RPC format (one JSON string per line).
	3.	✅ Avoid breaking on escaped newlines \n inside string values.
	4.	✅ Handle partial/buffered STDIN reads and message reassembly correctly.
	5.	✅ Gracefully handle invalid JSON or oversized lines with error logging.
	6.	✅ Stay compliant with initialize, prompts/list, and prompts/get.

🔧 Tasks
	•	Rewrite or improve read_line logic to correctly accumulate until full newline is reached.
	•	Use a read buffer strategy that prevents premature splitting or truncation.
	•	Ensure output to STDOUT flushes immediately after sending JSON-RPC response.
	•	Add clear error messages for:
	•	JSON parse failures
	•	Message too long
	•	Missing required fields
	•	Optionally: add a test mode that simulates large input through pipes or fixtures.

📁 File to Improve

stdio_transport.rb

# Your existing implementation here...
# Insert or paste full file content or work from this file structure.

🧪 Context
	•	The JSON input can contain long string values (e.g., transcripts).
	•	Clients like Claude Desktop and Continue use strict STDIO only.
	•	Escaped newlines (\n) should not be interpreted as message boundaries.

🧷 Example Input (1-line JSON-RPC with long transcript)

{"jsonrpc":"2.0","id":3,"method":"prompts/get","params":{"name":"SummarizeTranscriptPrompt","arguments":{"transcript":"OpenAI just published this paper... <over 20k characters>","meta":{"source":"manual test"}}}}

EXAMPLE - how it can be done:

```ruby
require 'json'

class StdioTransport
  def initialize
    @input = $stdin
    @output = $stdout
    @buffer = ""
  end

  def run(&handle_message)
    loop do
      begin
        # Read a full line (JSON-RPC spec says one JSON per line)
        line = @input.gets
        break if line.nil?

        # Clean line endings and append to buffer
        line.strip!
        next if line.empty?

        # Attempt to parse complete JSON message
        message = JSON.parse(line)
        log_debug("Received JSON-RPC message", message)

        # Handle and respond
        response = handle_message.call(message)
        send(response) if response
      rescue JSON::ParserError => e
        log_error("JSON parsing failed", e.message)
        send_error(-32700, "Parse error: Invalid JSON", nil)
      rescue => e
        log_error("Unexpected error", e.message)
        send_error(-32000, "Internal server error", nil)
      end
    end
  end

  def send(payload)
    json = payload.to_json
    @output.puts(json)
    @output.flush
  rescue => e
    log_error("Failed to send response", e.message)
  end

  def send_error(code, message, id = nil)
    error_payload = {
      jsonrpc: "2.0",
      id: id,
      error: {
        code: code,
        message: message
      }
    }
    send(error_payload)
  end

  private

  def log_debug(label, obj)
    $stderr.puts "[DEBUG] #{label}: #{obj.inspect}"
  end

  def log_error(label, message)
    $stderr.puts "[ERROR] #{label}: #{message}"
  end
end
```
