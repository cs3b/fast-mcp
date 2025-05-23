# frozen_string_literal: true

require_relative 'base_transport'

module MCP
  module Transports
    # STDIO transport for MCP
    # This transport uses standard input/output for communication
    class StdioTransport < BaseTransport
      def initialize(server, logger: nil)
        super
        @running = false
      end

      # Start the transport
      def start
        @logger.info('Starting STDIO transport')
        @running = true

        # Process input from stdin
        while @running && (line = $stdin.gets)
          begin
            response = process_message(line.strip)
            # Only send response if it's not nil (notifications don't need responses)
            if response
              # Don't store the return value to avoid accidental logging
              send_message(response)
            end
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
        # Don't return or output anything that could be accidentally logged
        nil
      end

      private

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
