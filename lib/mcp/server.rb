# frozen_string_literal: true

require 'json'
require 'logger'
require 'securerandom'
require 'base64'
require_relative 'transports/stdio_transport'
require_relative 'transports/rack_transport'
require_relative 'transports/authenticated_rack_transport'
require_relative 'logger'
require_relative 'prompt'

module MCP
  class Server
    attr_reader :name, :version, :tools, :resources, :prompts, :logger, :transport, :capabilities

    DEFAULT_CAPABILITIES = {
      resources: {
        subscribe: true,
        listChanged: true
      },
      tools: {
        listChanged: true
      },
      prompts: {
        listChanged: true
      }
    }.freeze

    def initialize(name:, version:, logger: MCP::Logger.new, capabilities: {})
      @name = name
      @version = version
      @tools = {}
      @resources = {}
      @prompts = {}
      @resource_subscriptions = {}
      @logger = logger
      @logger.level = Logger::INFO
      @request_id = 0
      @transport = nil
      @capabilities = DEFAULT_CAPABILITIES.dup

      # Merge with provided capabilities
      @capabilities.merge!(capabilities) if capabilities.is_a?(Hash)
    end

    def register_tools(*tools)
      tools.each do |tool|
        register_tool(tool)
      end
    end

    # Register a tool with the server
    def register_tool(tool)
      @tools[tool.tool_name] = tool
      @logger.info("Registered tool: #{tool.tool_name}")
    end

    # Register multiple resources at once
    # @param resources [Array<Resource>] Resources to register
    def register_resources(*resources)
      resources.each do |resource|
        register_resource(resource)
      end
    end

    # Register a resource with the server
    def register_resource(resource)
      @resources[resource.uri] = resource
      @logger.info("Registered resource: #{resource.name} (#{resource.uri})")

      # Notify subscribers about the list change
      notify_resource_list_changed if @transport

      resource
    end
    
    # Register multiple prompts at once
    # @param prompts [Array<Prompt>] Prompts to register
    def register_prompts(*prompts)
      prompts.each do |prompt|
        register_prompt(prompt)
      end
    end
    
    # Register a prompt with the server
    # @param prompt [Prompt] Prompt to register
    def register_prompt(prompt)
      @prompts[prompt.name] = prompt
      @logger.info("Registered prompt: #{prompt.name}")

      # Notify clients about the list change
      notify_prompts_list_changed if @transport

      prompt
    end
    
    # Remove a prompt from the server
    # @param name [String] Name of the prompt to remove
    # @return [Boolean] True if the prompt was removed, false otherwise
    def remove_prompt(name)
      if @prompts.key?(name)
        prompt = @prompts.delete(name)
        @logger.info("Removed prompt: #{name}")

        # Notify clients about the list change
        notify_prompts_list_changed if @transport

        true
      else
        false
      end
    end

    # Remove a resource from the server
    def remove_resource(uri)
      if @resources.key?(uri)
        resource = @resources.delete(uri)
        @logger.info("Removed resource: #{resource.name} (#{uri})")

        # Notify subscribers about the list change
        notify_resource_list_changed if @transport

        true
      else
        false
      end
    end

    # Start the server using stdio transport
    def start
      @logger.transport = :stdio
      @logger.info("Starting MCP server: #{@name} v#{@version}")
      @logger.info("Available tools: #{@tools.keys.join(', ')}")
      @logger.info("Available resources: #{@resources.keys.join(', ')}")

      # Use STDIO transport by default
      @transport = MCP::Transports::StdioTransport.new(self, logger: @logger)
      @transport.start
    end

    # Start the server as a Rack middleware
    def start_rack(app, options = {})
      @logger.info("Starting MCP server as Rack middleware: #{@name} v#{@version}")
      @logger.info("Available tools: #{@tools.keys.join(', ')}")
      @logger.info("Available resources: #{@resources.keys.join(', ')}")

      # Use Rack transport
      @transport = MCP::Transports::RackTransport.new(self, app, options.merge(logger: @logger))
      @transport.start

      # Return the transport as middleware
      @transport
    end

    def start_authenticated_rack(app, options = {})
      @logger.info("Starting MCP server as Authenticated Rack middleware: #{@name} v#{@version}")
      @logger.info("Available tools: #{@tools.keys.join(', ')}")
      @logger.info("Available resources: #{@resources.keys.join(', ')}")

      # Use Rack transport
      @transport = MCP::Transports::AuthenticatedRackTransport.new(self, app, options.merge(logger: @logger))
      @transport.start

      # Return the transport as middleware
      @transport
    end

    # Handle incoming JSON-RPC request
    def handle_request(json_str) # rubocop:disable Metrics/MethodLength
      begin
        request = JSON.parse(json_str)
      rescue JSON::ParserError, TypeError
        return send_error(-32_600, 'Invalid Request', nil)
      end

      @logger.debug("Received request: #{request.inspect}")

      # Check if it's a valid JSON-RPC 2.0 request
      unless request['jsonrpc'] == '2.0' && request['method']
        return send_error(-32_600, 'Invalid Request', request['id'])
      end

      method = request['method']
      params = request['params'] || {}
      id = request['id']

      # Check if it's a notification (no ID) or a request (with ID)
      is_notification = id.nil?
      
      # Special handling for notifications
      if is_notification && method == 'notifications/initialized'
        handle_initialized_notification
        return nil # Return nil for notifications as they don't expect a response
      end
      
      # Regular method handling (expecting responses with IDs)
      case method
      when 'ping'
        send_result({}, id)
      when 'initialize'
        handle_initialize(params, id)
      when 'tools/list'
        handle_tools_list(id)
      when 'tools/call'
        handle_tools_call(params, id)
      when 'resources/list'
        handle_resources_list(id)
      when 'resources/read'
        handle_resources_read(params, id)
      when 'resources/subscribe'
        handle_resources_subscribe(params, id)
      when 'resources/unsubscribe'
        handle_resources_unsubscribe(params, id)
      when 'prompts/list'
        handle_prompts_list(params, id)
      when 'prompts/get'
        handle_prompts_get(params, id)
      else
        send_error(-32_601, "Method not found: #{method}", id)
      end
    rescue StandardError => e
      @logger.error("Error handling request: #{e.message}, #{e.backtrace.join("\n")}")
      send_error(-32_600, "Internal error: #{e.message}", id)
    end

    # Handle a JSON-RPC request and return the response as a JSON string
    # Returns nil for notifications which don't require a response
    def handle_json_request(request)
      # Process the request
      response = if request.is_a?(String)
                   handle_request(request)
                 else
                   handle_request(JSON.generate(request))
                 end
      
      # Return nil for notifications (no response needed)
      return nil if response.nil?
      
      response
    end

    # Register a callback for resource updates
    def on_resource_update(&block)
      @resource_update_callbacks ||= []
      callback_id = SecureRandom.uuid
      @resource_update_callbacks << { id: callback_id, callback: block }
      callback_id
    end

    # Remove a resource update callback
    def remove_resource_update_callback(callback_id)
      @resource_update_callbacks ||= []
      @resource_update_callbacks.reject! { |cb| cb[:id] == callback_id }
    end

    # Update a resource and notify subscribers
    def update_resource(uri, content)
      return false unless @resources.key?(uri)

      resource = @resources[uri]
      resource.instance.content = content

      # Notify subscribers
      notify_resource_updated(uri) if @transport && @resource_subscriptions.key?(uri)

      # Notify resource update callbacks
      if @resource_update_callbacks && !@resource_update_callbacks.empty?
        @resource_update_callbacks.each do |cb|
          cb[:callback].call(
            {
              uri: uri,
              name: resource.name,
              mime_type: resource.mime_type,
              content: content
            }
          )
        end
      end

      true
    end

    # Read a resource directly
    def read_resource(uri)
      resource = @resources[uri]
      raise "Resource not found: #{uri}" unless resource

      resource
    end

    private

    PROTOCOL_VERSION = '2024-11-05'

    def handle_initialize(params, id)
      params['protocolVersion']
      client_capabilities = params['capabilities'] || {}
      client_info = params['clientInfo'] || {}

      # Log client information
      @logger.info("Client connected: #{client_info['name']} v#{client_info['version']}")
      # @logger.debug("Client capabilities: #{client_capabilities.inspect}")

      # Prepare server response
      response = {
        protocolVersion: PROTOCOL_VERSION, # For now, only version 2024-11-05 is supported.
        capabilities: @capabilities,
        serverInfo: {
          name: @name,
          version: @version
        }
      }

      @logger.info("Server response: #{response.inspect}")

      # Store client capabilities for later use
      @client_capabilities = client_capabilities

      send_result(response, id)
    end

    # Handle a resource read
    def handle_resources_read(params, id)
      uri = params['uri']

      return send_error(-32_602, 'Invalid params: missing resource URI', id) unless uri

      resource = @resources[uri]
      return send_error(-32_602, "Resource not found: #{uri}", id) unless resource

      base_content = { uri: resource.uri }
      base_content[:mimeType] = resource.mime_type if resource.mime_type
      resource_instance = resource.instance
      # Format the response according to the MCP specification
      result = if resource_instance.binary?
                 {
                   contents: [base_content.merge(blob: Base64.strict_encode64(resource_instance.content))]
                 }
               else
                 {
                   contents: [base_content.merge(text: resource_instance.content)]
                 }
               end

      send_result(result, id)
    end

    def handle_initialized_notification
      # The client is now ready for normal operation
      # No response needed for notifications
      @client_initialized = true
      @logger.set_client_initialized
      @logger.info('Client initialized, beginning normal operation')
    end

    # Handle tools/list request
    def handle_tools_list(id)
      tools_list = @tools.values.map do |tool|
        {
          name: tool.tool_name,
          description: tool.description || '',
          inputSchema: tool.input_schema_to_json || { type: 'object', properties: {}, required: [] }
        }
      end

      send_result({ tools: tools_list }, id)
    end

    # Handle tools/call request
    def handle_tools_call(params, id)
      tool_name = params['name']
      arguments = params['arguments'] || {}

      return send_error(-32_602, 'Invalid params: missing tool name', id) unless tool_name

      tool = @tools[tool_name]
      return send_error(-32_602, "Tool not found: #{tool_name}", id) unless tool

      begin
        # Convert string keys to symbols for Ruby
        symbolized_args = symbolize_keys(arguments)
        result = tool.new.call_with_schema_validation!(**symbolized_args)

        # Format and send the result
        send_formatted_result(result, id)
      rescue MCP::Tool::InvalidArgumentsError => e
        @logger.error("Invalid arguments for tool #{tool_name}: #{e.message}")
        send_error_result(e.message, id)
      rescue StandardError => e
        @logger.error("Error calling tool #{tool_name}: #{e.message}")
        send_error_result("#{e.message}, #{e.backtrace.join("\n")}", id)
      end
    end

    # Format and send successful result
    def send_formatted_result(result, id)
      # Check if the result is already in the expected format
      if result.is_a?(Hash) && result.key?(:content)
        # Result is already in the correct format
        send_result(result, id)
      else
        # Format the result according to the MCP specification
        formatted_result = {
          content: [{ type: 'text', text: result.to_s }],
          isError: false
        }
        send_result(formatted_result, id)
      end
    end

    # Format and send error result
    def send_error_result(message, id)
      # Format error according to the MCP specification
      error_result = {
        content: [{ type: 'text', text: "Error: #{message}" }],
        isError: true
      }
      send_result(error_result, id)
    end

    # Handle resources/list request
    def handle_resources_list(id)
      resources_list = @resources.values.map(&:metadata)

      send_result({ resources: resources_list }, id)
    end

    # Handle resources/subscribe request
    def handle_resources_subscribe(params, id)
      return unless @client_initialized

      uri = params['uri']

      unless uri
        send_error(-32_602, 'Invalid params: missing resource URI', id)
        return
      end

      resource = @resources[uri]
      unless resource
        send_error(-32_602, "Resource not found: #{uri}", id)
        return
      end

      # Add to subscriptions
      @resource_subscriptions[uri] ||= []
      @resource_subscriptions[uri] << id

      send_result({ subscribed: true }, id)
    end

    # Handle resources/unsubscribe request
    def handle_resources_unsubscribe(params, id)
      return unless @client_initialized

      uri = params['uri']

      unless uri
        send_error(-32_602, 'Invalid params: missing resource URI', id)
        return
      end

      # Remove from subscriptions
      if @resource_subscriptions.key?(uri)
        @resource_subscriptions[uri].delete(id)
        @resource_subscriptions.delete(uri) if @resource_subscriptions[uri].empty?
      end

      send_result({ unsubscribed: true }, id)
    end

    # Handle prompts/list request
    # @param params [Hash] Request parameters (pagination support)
    # @param id [Object] Request ID for response correlation
    def handle_prompts_list(params, id)
      cursor = params['cursor'] if params
      # For now, no pagination is implemented - return all prompts
      
      prompts_list = @prompts.values.map(&:to_list_hash)
      
      # In a future version, implement pagination with cursor
      result = { prompts: prompts_list }
      # result[:nextCursor] = next_cursor if next_cursor

      send_result(result, id)
    end

    # Handle prompts/get request
    # @param params [Hash] Request parameters (prompt name and arguments)
    # @param id [Object] Request ID for response correlation
    def handle_prompts_get(params, id)
      prompt_name = params['name']
      arguments = params['arguments'] || {}

      return send_error(-32_602, 'Invalid params: missing prompt name', id) unless prompt_name

      prompt = @prompts[prompt_name]
      return send_error(-32_602, "Prompt not found: #{prompt_name}", id) unless prompt

      begin
        # Get the prompt content with the provided arguments
        result = prompt.get_content(arguments)
        send_result(result, id)
      rescue StandardError => e
        @logger.error("Error getting prompt #{prompt_name}: #{e.message}")
        send_error(-32_602, "Error: #{e.message}", id)
      end
    end

    # Notify subscribers about a resource update
    def notify_resource_updated(uri)
      return unless @client_initialized && @resource_subscriptions.key?(uri)

      resource = @resources[uri]
      notification = {
        jsonrpc: '2.0',
        method: 'notifications/resources/updated',
        params: {
          uri: uri,
          name: resource.name,
          mimeType: resource.mime_type
        }
      }

      @transport.send_message(notification)
    end

    # Notify clients about resource list changes
    def notify_resource_list_changed
      return unless @client_initialized

      notification = {
        jsonrpc: '2.0',
        method: 'notifications/resources/listChanged',
        params: {}
      }

      @transport.send_message(notification)
    end
    
    # Notify clients about prompt list changes
    def notify_prompts_list_changed
      return unless @client_initialized

      notification = {
        jsonrpc: '2.0',
        method: 'notifications/prompts/list_changed',
        params: {}
      }

      @transport.send_message(notification)
    end

    # Send a JSON-RPC result response
    def send_result(result, id)
      response = {
        jsonrpc: '2.0',
        id: id,
        result: result
      }

      @logger.info("Sending result: #{response.inspect}")
      send_response(response)
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
      send_response(response)
    end

    # Send a JSON-RPC response
    def send_response(response)
      if @transport
        @logger.info("Sending response: #{response.inspect}")
        @logger.debug("Using transport: #{@transport.class.name}")
        @transport.send_message(response)
      else
        @logger.warn("No transport available to send response: #{response.inspect}")
      end
    end

    # Helper method to convert string keys to symbols
    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        new_key = key.is_a?(String) ? key.to_sym : key
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end
  end
end
