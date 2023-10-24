# frozen_string_literal: true

require "canister/version"
require "delegate"
# A container that registers keys to values that are
# resolved at runtime. This allows for out-of-order declaration,
# automatic dependency resolution, and--upon
# redeclaration--automatic dependency cache invalidation.
class Canister < SimpleDelegator

  def initialize(&blk)
    @context_stack = []
    push_context!(new_context: Context.new)
    yield self if block_given?
  end

  # @overload Context#register() so it can return 'self' and not the context
  def register(*args, **kwargs, &blk)
    @context.register(*args, **kwargs, &blk)
    self
  end

  # Push a new (presumably temporary) context onto the stack from which to resolve values
  # @param new_context [Context] The new context; by default, just a copy of the current registry
  # @return [Canister] self
  def push_context!(new_context: @context.dup)
    @context_stack.push(new_context)
    @context = @context_stack.last
    __setobj__(@context)
    self
  end

  # Pop a context off the stack, returning the resolution context to what it was before the last #push_context
  # @return [Canister] self
  def pop_context!
    raise "Can't pop context_stack if there's only one thing in it" unless @context_stack.size > 1
    @context_stack.pop
    @context = @context_stack.last
    __setobj__(@context)
  end

  # Evaluate the given block in a fresh context, allowing temporary overrides to registered procs.
  # NOT THREAD SAFE. NOT EVEN A LITTLE.
  # @return [Canister] self
  def override(&blk)
    push_context!
    blk.call
    pop_context!
    self
  end

  class Context

    # Set up a new context within which to register/resolve
    def initialize(stack: [], registry: {}, resolved: {}, dependents: Hash.new { |h, k| h[k] = [] })
      @stack = stack
      @registry = registry
      @resolved = resolved
      @dependents = dependents
      @mutex = Mutex.new
    end

    # Create a new context based on the current one by copying the registry and leaving everything else empty
    # @return [Context] A new Context with a duplicate of the old registry
    def dup
      self.class.new(registry: @registry)
    end

    # We override method_missing to enable dot notation
    # for accessing registered values.
    def method_missing(method, *args, &block)
      if handles?(method)
        resolve(method)
      else
        super(method, *args, block)
      end
    end

    # We override respond_to? to enable dot notation
    # for accessing registered values.
    def respond_to_missing?(method, include_all = false)
      handles?(method) || super(method, include_all)
    end

    # Run the given block in a local mutex
    def synchronize(&block)
      if @mutex.owned?
        yield
      else
        @mutex.synchronize(&block)
      end
    end

    # Register a value to a key by passing a block. Note that
    # the value will be that returned by the block. If the key
    # has been registered before, the old registration is
    # overwritten. Dependents of the original registration
    # are automatically invalidated.
    # @param key [Symbol] The "name" of the registered key
    # @yieldparam self [Context] Yields this container.
    # @yieldreturn the value defined in the block
    # @return [Context] self
    def register(key, &block)
      key = key.to_sym
      synchronize do
        invalidate(key) if registered?(key)
        registry[key] = block
      end
      self
    end

    # Recursively resolves the object that was registered to
    # the key. This value is memoized.
    # @param key [Symbol]
    def resolve(key)
      key = key.to_sym
      value = nil
      synchronize do
        add_dependent(key)
        stack << key
        value = resolved[key] ||= registry[key].call(self)
        stack.pop
      end
      value
    end

    alias_method :[], :resolve

    def keys
      registry.keys
    end

    private

    attr_reader :dependents, :registry, :resolved, :stack

    def handles?(method)
      registered?(method)
    end

    def add_dependent(key)
      unless stack.empty?
        dependents[key] << stack.last
      end
    end

    def registered?(key)
      registry.key?(key)
    end

    def unresolve(key)
      resolved.delete(key)
    end

    def invalidate(key, first = true)
      unresolve(key)
      dependents[key]
        .each { |child| invalidate(child, false) }
      if first
        dependents.delete(key)
      end
    end
  end
end
