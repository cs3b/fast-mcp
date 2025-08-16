# Migration Guide: v1.2.0 to v1.6.0

This guide will help you migrate your Fast MCP application from version 1.2.0 to 1.6.0. The new version includes several breaking changes and new features that require updates to your existing code.

## Breaking Changes

### 1. Stateless Resources

The most significant breaking change is that resources are now stateless. This change was introduced in v1.5.0 to improve scalability and enable resource templates.

**Before (Singleton):**
```ruby
class CounterResource < FastMcp::Resource
  include Singleton
  def initialize
    @count = 0
  end
  
  def content
    @count.to_s
  end
  
  def increment
    @count += 1
    notify_resource_updated
  end
end
```

**After (Stateless):**
```ruby
class CounterResource < FastMcp::Resource
  def content
    File.read('counter.txt') rescue '0'
  end
  
  def increment
    current_count = content.to_i
    File.write('counter.txt', (current_count + 1).to_s)
    notify_resource_updated
  end
end
```

**Migration Steps:**
1. Remove `include Singleton` from resource classes
2. Replace instance variables with external data sources (files, databases, etc.)
3. Update any code that relied on persistent state within the resource instance

### 2. Resource Registration

Resource registration has changed due to the removal of the singleton pattern.

**Before:**
```ruby
server.register_resource(MyResource.instance)
```

**After:**
```ruby
server.register_resource(MyResource.new)
```

**Migration Steps:**
1. Update all `register_resource` calls to use `.new` instead of `.instance`
2. Remove any manual singleton instantiation code

### 3. Server Filtering

A new filtering architecture has been introduced that requires including the `ServerFiltering` module in custom servers.

**Before:**
```ruby
class MyServer < FastMcp::Server
  # No filtering support
end
```

**After:**
```ruby
class MyServer < FastMcp::Server
  include ServerFiltering
  
  def initialize(*)
    super
    setup_filtering
  end
end
```

**Migration Steps:**
1. Add `include ServerFiltering` to any custom server classes
2. Call `setup_filtering` in the server initialization if you plan to use filtering

### 4. Prompt Headers

All prompts now accept a headers parameter for enhanced request context.

**Before:**
```ruby
class MyPrompt < FastMcp::Prompt
  def call(arg1:, arg2:)
    # Prompt implementation
  end
end
```

**After:**
```ruby
class MyPrompt < FastMcp::Prompt
  def call(arg1:, arg2:, headers: {})
    # Prompt implementation
    # Can now access request headers if needed
  end
end
```

**Migration Steps:**
1. Update prompt `call` methods to accept an optional `headers` parameter
2. Use the headers parameter if you need access to request context

## New Features

### 1. Enhanced Tool Features

Tools now support additional metadata and authorization features:

```ruby
class MyTool < FastMcp::Tool
  # New annotation support
  annotations(
    title: 'My Tool',
    read_only_hint: true,
    destructive_hint: false
  )
  
  # New tag support
  tags :utility, :safe
  
  # Enhanced metadata
  metadata version: '2.0', category: 'utils'
  
  # Authorization support
  authorize { |user:| user.has_permission?(:use_tool) }
end
```

### 2. Prompt Filtering and Authorization

Prompts now support the same filtering and authorization patterns as tools:

```ruby
# Server-level prompt filtering
server.filter_prompts do |request, prompts|
  prompts.select { |p| p.authorized?(user: request.user) }
end

# Prompt-level authorization
class SecurePrompt < FastMcp::Prompt
  authorize { |user:| user.is_admin? }
end
```

### 3. Resource Templates

Resources now support template-based content generation:

```ruby
class TemplateResource < FastMcp::Resource
  template 'user_profile.erb'
  
  def template_data
    {
      user: current_user,
      timestamp: Time.now
    }
  end
end
```

## Recommended Upgrade Path

### Step 1: Update Dependencies

Update your Gemfile:

```ruby
gem 'fast-mcp', '~> 1.6.0'
```

Run `bundle update fast-mcp`.

### Step 2: Fix Resource Classes

1. Identify all resource classes that use the singleton pattern
2. Refactor them to use external data sources instead of instance variables
3. Update registration calls to use `.new` instead of `.instance`

### Step 3: Update Server Configuration

If you have custom server classes:

1. Add `include ServerFiltering`
2. Update initialization to call `setup_filtering` if using filtering

### Step 4: Review Prompt Classes

1. Add optional `headers` parameter to prompt `call` methods
2. Consider adding authorization or filtering if needed

### Step 5: Test Thoroughly

1. Run your existing test suite
2. Test resource state persistence
3. Verify tool and prompt functionality
4. Test any filtering or authorization logic

## Common Migration Issues

### Issue: Resource State Not Persisting

**Problem:** Resources lose state between requests.

**Solution:** Implement external storage for resource state:

```ruby
# Use a database, file, or cache instead of instance variables
def content
  Rails.cache.fetch("resource_#{uri}") { load_from_database }
end
```

### Issue: Server Not Recognizing Filtering

**Problem:** Filtering methods not available on server.

**Solution:** Ensure you've included the `ServerFiltering` module:

```ruby
class MyServer < FastMcp::Server
  include ServerFiltering
end
```

### Issue: Headers Not Available in Prompts

**Problem:** Cannot access request headers in prompt methods.

**Solution:** Update prompt method signature:

```ruby
def call(query:, headers: {})
  auth_token = headers['Authorization']
  # Use auth_token as needed
end
```

## Version Compatibility

- **Minimum Ruby Version:** 3.0+
- **Rails Compatibility:** 6.0+ (if using Rails integration)
- **Backward Compatibility:** Limited due to resource stateless changes

## Getting Help

If you encounter issues during migration:

1. Check the [documentation](https://github.com/yjacquin/fast-mcp/tree/main/docs)
2. Review the [examples](https://github.com/yjacquin/fast-mcp/tree/main/examples)
3. Open an issue on [GitHub](https://github.com/yjacquin/fast-mcp/issues)

## Summary

The migration from v1.2.0 to v1.6.0 primarily involves:

1. **Converting singleton resources to stateless resources** - The biggest change requiring code updates
2. **Updating resource registration calls** - Simple find-and-replace operation
3. **Adding filtering support to custom servers** - Optional unless you need filtering
4. **Updating prompt headers handling** - Optional unless you need request context

Most applications will only need to handle the resource changes, making this a manageable migration for most use cases.