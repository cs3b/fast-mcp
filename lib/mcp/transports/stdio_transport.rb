# frozen_string_literal: true

require_relative 'base_transport'

module FastMcp
  module Transports
    # STDIO transport for MCP
    # This transport uses standard input/output for communication
    class StdioTransport < BaseTransport
      def initialize(server, logger: nil)
        super
        @running = false
        @buffer = ''
        @max_line_size = 1024 * 1024 # 1MB max line size for safety
      end

      # Start the transport
      def start
        @logger.info('Starting STDIO transport')
        @running = true

        # Process input from stdin
        while @running
          begin
            line = read_line
            break if line.nil?
            next if line.empty?

            process_message(line)
          rescue JSON::ParserError => e
            @logger.error("JSON parsing error: #{e.message}")
            send_error(-32_700, "Parse error: Invalid JSON")
          rescue StandardError => e
            @logger.error("Error processing message: #{e.message}")
            @logger.error(e.backtrace.join("\n"))
            send_error(-32_000, "Internal error: #{e.message}")
          end
        end
      end

      # Stop the transport
      def stop
        @logger.info('Stopping STDIO transport')
        @running = false
      end

      # Send a message to the client
      def send_message(message)
        json_message = message.is_a?(String) ? message : JSON.generate(message)

        $stdout.puts(json_message)
        $stdout.flush
      end

      private

      # Read a complete line from stdin, handling large inputs correctly
      def read_line
        while @running
          chunk = $stdin.read_nonblock(8192, exception: false)
          
          case chunk
          when :wait_readable
            $stdin.wait_readable
            next
          when nil
            return nil
          else
            @buffer += chunk
          end

          # Process complete lines
          if @buffer.include?("\n")
            line, @buffer = @buffer.split("\n", 2)
            
            if line.bytesize > @max_line_size
              @logger.error("Message exceeds maximum size of #{@max_line_size} bytes")
              send_error(-32_001, "Message too large")
              @buffer = ''
              next
            end
            
            return line.strip
          end

          # Safety check for buffer size
          if @buffer.bytesize > @max_line_size
            @logger.error("Input buffer exceeds maximum size of #{@max_line_size} bytes")
            send_error(-32_001, "Message too large")
            @buffer = ''
          end
        end
      rescue StandardError => e
        @logger.error("IO error while reading: #{e.message}")
        nil
      end

      # Send a JSON-RPC error response
      def send_error(code, message, id = nil)
        response = {
          jsonrpc: '2.0',
          error: {
            code: code,
            message: message
          },
          id: id
        }
        send_message(response)
      end
    end
  end
end
