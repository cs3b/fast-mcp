# frozen_string_literal: true

class SamplePrompt < ApplicationPrompt
  prompt_name "sample_prompt"
  description "A sample prompt to demonstrate functionality"
  
  # Define arguments using Dry::Schema syntax
  arguments do
    required(:input).filled(:string).description("The input to process")
    optional(:context).filled(:string).description("Additional context")
  end
  
  # Define the prompt template
  template do |args|
    messages = []
    messages << {
      role: "system",
      content: "You are a helpful assistant."
    }
    messages << {
      role: "user",
      content: "Process this input: #{args[:input]}"
    }
    messages << {
      role: "user",
      content: "Context: #{args[:context]}"
    } if args[:context]
    
    messages
  end
end