# frozen_string_literal: true

require_relative "spec_helper"
require "canister"

RSpec.describe Canister do
  let(:canister) { described_class.new }

  it "has a version number" do
    expect(Canister::VERSION).not_to be nil
  end

  it "#new takes a block" do
    container = described_class.new do |c|
      c.register(:foo) { :bar }
    end
    expect(container.resolve(:foo)).to eql(:bar)
  end

  it "resolves a simple variable" do
    canister.register(:foo) { :bar }
    expect(canister.resolve(:foo)).to eql(:bar)
  end

  it "#[] is equivalent to #resolve" do
    canister.register(:foo) { :bar }
    expect(canister[:foo]).to eql(canister.resolve(:foo))
  end

  it ".foo is equivalent to #resolve(:foo)" do
    canister.register(:foo) { :bar }
    expect(canister.foo).to eql(canister.resolve(:foo))
  end

  it "can resolve a symbol with a string" do
    canister.register(:foo) { :bar }
    expect(canister.resolve("foo")).to eql(:bar)
  end

  it "can resolve a string with a symbol" do
    canister.register("foo") { :bar }
    expect(canister.resolve(:foo)).to eql(:bar)
  end

  it "#register returns self" do
    expect(canister.register(:foo) {}).to eql(canister)
  end

  it "memoizes the value" do
    counter = 0
    canister.register(:foo) { counter += 1 }
    canister.resolve(:foo)
    expect(canister.resolve(:foo)).to eql(1)
  end

  it "correctly sends method_missing for a missing key" do
    expect { canister.to_s }.not_to raise_error
    expect { canister.foo  }.to raise_error(NoMethodError)
  end

  it "correctly answers #respond_to?" do
    canister.register(:bar) { "bar" }
    expect(canister.respond_to?(:to_s)).to be true
    expect(canister.respond_to?(:foo)).to be false
    expect(canister.respond_to?(:bar)).to be true
  end

  it "#keys returns the keys" do
    canister.register(:foo) { :bar }
    canister.register(:alice) { :bob }
    expect(canister.keys).to contain_exactly(:foo, :alice)
  end

  it "allows nesting" do
    canister.register(:a) { "a" }
    canister.register(:b) {|c| c.a + "b" }
    canister.register(:c) {|c| c.b + "c" }
    expect(canister.resolve(:c)).to eql("abc")
  end

  it "allows a complex tree" do
    canister.register(:a) { "a" }
    canister.register(:b1) {|c| c.a + "b1" }
    canister.register(:b2) {|c| c.a + "b2" }
    canister.register(:c) {|c| c.b1 + c.b2 + "c" }
    expect(canister.resolve(:c)).to eql("ab1ab2c")
  end

  it "resets the dependency sequence on reregister" do
    canister.register(:a) { "a" }
    canister.register(:b) {|c| c.a + "b" }
    canister.register(:c) {|c| c.b + "c" }
    canister.register(:d) {|c| c.c + "d" }
    canister.register(:e) {|c| c.d + "e" }
    canister.register(:f) {|c| c.e + "f" }
    canister.resolve(:f)
    canister.register(:a) { "x" }
    expect(canister.resolve(:f)).to eql("xbcdef")
  end

  it "resets the dependency tree on reregister" do
    canister.register(:a) { "a" }
    canister.register(:b1) {|c| c.a + "b1" }
    canister.register(:b2) {|c| c.a + "b2" }
    canister.register(:c) {|c| c.b1 + c.b2 + "c" }
    canister.resolve(:c)
    canister.register(:a) { "x" }
    expect(canister.resolve(:c)).to eql("xb1xb2c")
  end

  it "ignores order" do
    canister.register(:c) {|c| c.b + "c" }
    canister.register(:b) {|c| c.a + "b" }
    canister.register(:a) { "a" }
    expect(canister.resolve(:c)).to eql("abc")
  end

  it "is apparently thread safe" do
    threads = []
    canister.register(:a) { "a" }
    1000.times do
      canister.register(:b) do |c|
        threads << Thread.new do
          loop do
            sleep 0.1
            c[:a]
          end
        end
        "b"
      end
      canister.resolve(:b)
    end
    sleep 3
    expect(canister.resolve(:b)).to eql("b")
    threads.each(&:kill)
  end
end
