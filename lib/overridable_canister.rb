# frozen_string_literal: true

require "canister"
require "delegate"

# A OverridableCanister behaves exactly like a canister except you can temporarily
# modify it, presumably for purposes of testing.
# It should be a drop-in replacement for Canister
# @example Create a new OverridableCanister
#   C = OverridableCanister.new
# @example Create a new OverridableCanister based on an existing Canister.
#  # Note that existing_canister is NOT cloned -- changes made to
#  # The OverridableCanister while the initial canister (i.e., existing_canister)
#  # is active will change that underlying canister
#  C = OverridableCanister.new(existing_canister)
#  C.existing_key #=> existing_value
#
# @example Use #override to allow changes within the provided block and automatically roll them back afterward.
#   C = OverridableCanister.new
#   C.register(:name) { "Bill" }
#   C.register(:greeting) {|c| "Hello #{c.name}"}
#   puts C.greeting #=> "Hello Bill"
#   C.override do |c|
#     c.register(:name) { "Ziv" }
#     puts c.greeting #=> "Hello Ziv"
#   end
#   puts C.greeting #=> "Hello Bill"
#
# @example Push and pop contexts for temporary changes
#   C.push_context!
#   C.register(:name) { "Danit" }
#   puts C.greeting #=> "Hello Danit" }
#
#   C.push_context!
#   C.register(:greeting) { |c| "Hi there #{c.name}"}
#   puts C.greeting # => "Hi there Danit"
#
#   C.pop_context!
#   puts C.greeting #=> "Hello Danit"
#
#   C.pop_context!
#   puts C.greeting #=> "Hello Bill"

class OverridableCanister < SimpleDelegator
  # Create a new canister stack, optionally passing in an initial canister
  # @param initial_canister [Canister]
  def initialize(initial_canister = Canister.new)
    @contexts = [initial_canister]
    reset_delegate!
    yield self if block_given?
  end

  # @overload register(key, &block)
  # Overloaded so it can return self (meaning the OverridableCanister, not the
  # Canister that took the registration)
  def register(key, &block)
    super
    self
  end

  # Start a new context. Changes will only be valid until the matching
  # #pop_context! is called
  def push_context!
    @contexts.push @contexts.last.clone_self
    reset_delegate!
    self
  end

  # @see #push_context!
  def pop_context!
    @contexts.pop
    reset_delegate!
    self
  end

  # Temporarily override the canister within the given block.
  # Safe to call #override within an override, or to use
  # #push_context! / #pop_context!
  def override(&blk)
    orig_stack = @contexts.dup
    push_context!
    yield self
    @contexts = orig_stack
    reset_delegate!
    self
  end

  private

  def reset_delegate!
    __setobj__(@contexts.last)
  end
end
