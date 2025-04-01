# frozen_string_literal: true

require 'dry-schema'
require 'erb'

module FastMcp
  # Main Prompt class that represents an MCP Prompt
  class Prompt
    class InvalidArgumentsError < StandardError; end

    # Define roles as a hash with keys and text
    ROLES = {
      user: 'user',
      assistant: 'assistant'
    }.freeze

    CONTENT_TYPE_TEXT = 'text'
    CONTENT_TYPE_IMAGE = 'image'
    CONTENT_TYPE_RESOURCE = 'resource'

    class << self
      attr_accessor :server

      def arguments(&block)
        @input_schema = Dry::Schema.JSON(&block)
      end

      def input_schema
        @input_schema ||= Dry::Schema.JSON
      end

      def prompt_name(name = nil)
        if name.nil?
          return @name if @name
          # Get the actual class name without namespace
          class_name = self.name.to_s.split('::').last
          # Remove "Prompt" suffix and convert to snake_case
          return class_name.gsub(/Prompt$/, '').gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
        end

        @name = name
      end

      def description(description = nil)
        return @description if description.nil?

        @description = description
      end

      def call(**args)
        raise NotImplementedError, 'Subclasses must implement the call method'
      end

      def input_schema_to_json
        return nil unless @input_schema

        compiler = SchemaCompiler.new
        compiler.process(@input_schema)
      end
    end

    def call_with_schema_validation!(**args)
      arg_validation = self.class.input_schema.call(args)
      raise InvalidArgumentsError, arg_validation.errors.to_h.to_json if arg_validation.errors.any?

      call(**args)
    end

    # Create a message with the given role and content
    def message(role:, content:)
      validate_role(role)
      validate_content(content)

      {
        role: role,
        content: content
      }
    end

    # Create multiple messages from a hash of role => content pairs or an array of role-keyed hashes
    # @param args [Hash, Array<Hash>] Either a hash of role => content pairs or an array of single-key hashes with role as key
    # @return [Array<Hash>] An array of messages
    def messages(*args)
      result = []
      
      # Handle both hash and array arguments for backward compatibility
      if args.length == 1 && args.first.is_a?(Hash)
        # Original API: hash of role => content pairs
        messages_hash = args.first
        raise ArgumentError, 'At least one message must be provided' if messages_hash.empty?
        
        messages_hash.each do |role_key, content|
          # Extract the base role (without any suffix like _2)
          base_role = role_key.to_s.gsub(/_\d+$/, '')
          
          # Validate the role
          validate_role(base_role)
          
          # Add the message to the result
          if content.is_a?(Hash)
            result << message(role: base_role, content: content)
          else
            result << message(role: base_role, content: text_content(content))
          end
        end
      else
        # New API: array of single-key hashes with role as key
        raise ArgumentError, 'At least one message must be provided' if args.empty?
        
        args.each do |msg_hash|
          raise ArgumentError, 'Each message must be a hash' unless msg_hash.is_a?(Hash)
          
          # Each hash should have a single key (the role)
          msg_hash.each do |role_key, content|
            # Extract the base role (without any suffix like _2)
            base_role = role_key.to_s.gsub(/_\d+$/, '')
            
            # Validate the role
            validate_role(base_role)
            
            # Add the message to the result
            if content.is_a?(Hash)
              result << message(role: base_role, content: content)
            else
              result << message(role: base_role, content: text_content(content))
            end
          end
        end
      end

      result
    end
    
    # Helper method to extract content from a hash
    def content_from_hash(hash)
      if hash.key?(:text)
        text_content(hash[:text])
      elsif hash.key?(:data) && hash.key?(:mimeType)
        image_content(hash[:data], hash[:mimeType])
      elsif hash.key?(:resource)
        # It's already a resource content
        hash
      else
        # Default to text content with empty string
        text_content('')
      end
    end

    # Create a text content object
    def text_content(text)
      {
        type: CONTENT_TYPE_TEXT,
        text: text
      }
    end

    # Create an image content object
    def image_content(data, mime_type)
      {
        type: CONTENT_TYPE_IMAGE,
        data: data,
        mimeType: mime_type
      }
    end

    # Create a resource content object
    def resource_content(uri, mime_type, text: nil, blob: nil)
      resource = {
        uri: uri,
        mimeType: mime_type
      }

      resource[:text] = text if text
      resource[:blob] = blob if blob

      {
        type: CONTENT_TYPE_RESOURCE,
        resource: resource
      }
    end

    def validate_role(role)
      # Convert role to symbol if it's a string
      role_key = role.is_a?(String) ? role.to_sym : role
      
      # Use fetch with a block for better error handling
      ROLES.fetch(role_key) do
        raise ArgumentError, "Invalid role: #{role}. Must be one of: #{ROLES.keys.join(', ')}"
      end
    end

    def validate_content(content)
      unless content.is_a?(Hash) && content[:type]
        raise ArgumentError, "Invalid content: #{content}. Must be a hash with a :type key"
      end

      case content[:type]
      when CONTENT_TYPE_TEXT
        raise ArgumentError, "Missing :text in text content" unless content[:text]
      when CONTENT_TYPE_IMAGE
        raise ArgumentError, "Missing :data in image content" unless content[:data]
        raise ArgumentError, "Missing :mimeType in image content" unless content[:mimeType]
      when CONTENT_TYPE_RESOURCE
        validate_resource_content(content[:resource])
      else
        raise ArgumentError, "Invalid content type: #{content[:type]}"
      end
    end

    def validate_resource_content(resource)
      raise ArgumentError, "Missing :resource in resource content" unless resource
      raise ArgumentError, "Missing :uri in resource content" unless resource[:uri]
      raise ArgumentError, "Missing :mimeType in resource content" unless resource[:mimeType]
      raise ArgumentError, "Resource must have either :text or :blob" unless resource[:text] || resource[:blob]
    end
  end
end
