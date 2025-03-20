# frozen_string_literal: true

require "canister/version"

# A container that registers keys to values that are
# resolved at runtime. This allows for out-of-order declaration,
# automatic dependency resolution, and--upon
# redeclaration--automatic dependency cache invalidation.
# @param hashlike [#each_pair, #keys #[]]
# @see #fill_from_hashlike
class Canister
  def initialize(hashlike = nil)
    @stack = []
    @registry = {}
    @resolved = {}
    @dependents = Hash.new do |hash, key|
      hash[key] = []
    end
    @mutex = Mutex.new
    if hashlike
      self.fill_from_hashlike(hashlike)
    end
    yield self if block_given?
  end

  # A "hashlike" is defined as anything that responds to both #[]
  # and #keys and/or #each_pair
  # Each value is wrapped in a `proc` and registered under the key.
  # Note that Canister doesn't differentiate between symbols and
  # strings for keys, so if your hashlike has keys of, e.g. both
  # `"a"` and `:a` it won't work.
  def fill_from_hashlike(hashlike)
    iter = if hashlike.respond_to?(:each_pair)
             hashlike.each_pair
           else
             if [:[], :keys].all? { |meth| hashlike.respond_to?(:meth) }
               hashlike.lazy.keys.map { |k| [k, hashlike[h]] }
             else
               msg = "Need something that responds to either #each_pair or both #keys and #[]"
               raise ArgumentError.new(msg)
             end
           end
    iter.each do |k, v|
      blk = proc { v }
      register(k, &blk)
    end
    self
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
  # @param key [Symbol]
  # @yield self [Container] Yields this container.
  # @return the value defined in the block
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
