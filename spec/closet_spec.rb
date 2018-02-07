# frozen_string_literal: true
require_relative "spec_helper"
require "closet"

RSpec.describe Closet do
  it "has a version number" do
    expect(Closet::VERSION).not_to be nil
  end

  let(:closet) { described_class.new }

  it "#new takes a block" do
    container = described_class.new do |c|
      c.register(:foo) { :bar }
    end
    expect(container.resolve(:foo)).to eql(:bar)
  end

  it "resolves a simple variable" do
    closet.register(:foo) { :bar }
    expect(closet.resolve(:foo)).to eql(:bar)
  end

  it "#[] is equivalent to #resolve" do
    closet.register(:foo) { :bar }
    expect(closet[:foo]).to eql(closet.resolve(:foo))
  end

  it ".foo is equivalent to #resolve(:foo)" do
    closet.register(:foo) { :bar }
    expect(closet.foo).to eql(closet.resolve(:foo))
  end

  it "can resolve a symbol with a string" do
    closet.register(:foo) { :bar }
    expect(closet.resolve("foo")).to eql(:bar)
  end

  it "can resolve a string with a symbol" do
    closet.register("foo") { :bar }
    expect(closet.resolve(:foo)).to eql(:bar)
  end

  it "#register returns self" do
    expect(closet.register(:foo) {}).to eql(closet)
  end

  it "memoizes the value" do
    counter = 0
    closet.register(:foo) { counter += 1 }
    closet.resolve(:foo)
    expect(closet.resolve(:foo)).to eql(1)
  end

  it "correctly sends method_missing for a missing key" do
    expect { closet.to_s }.to_not raise_error
    expect { closet.foo  }.to raise_error(NoMethodError)
  end

  it "correctly answers #respond_to?" do
    closet.register(:bar) { "bar" }
    expect(closet.respond_to?(:to_s)).to be true
    expect(closet.respond_to?(:foo)).to be false
    expect(closet.respond_to?(:bar)).to be true
  end

  it "#keys returns the keys" do
    closet.register(:foo) { :bar }
    closet.register(:alice) { :bob }
    expect(closet.keys).to contain_exactly(:foo, :alice)
  end

  it "allows nesting" do
    closet.register(:a) { "a" }
    closet.register(:b) {|c| c.a + "b" }
    closet.register(:c) {|c| c.b + "c" }
    expect(closet.resolve(:c)).to eql("abc")
  end

  it "allows a complex tree" do
    closet.register(:a) { "a" }
    closet.register(:b1) {|c| c.a + "b1" }
    closet.register(:b2) {|c| c.a + "b2" }
    closet.register(:c) {|c| c.b1 + c.b2 + "c" }
    expect(closet.resolve(:c)).to eql("ab1ab2c")
  end

  it "resets the dependency sequence on reregister" do
    closet.register(:a) { "a" }
    closet.register(:b) {|c| c.a + "b" }
    closet.register(:c) {|c| c.b + "c" }
    closet.register(:d) {|c| c.c + "d" }
    closet.register(:e) {|c| c.d + "e" }
    closet.register(:f) {|c| c.e + "f" }
    closet.resolve(:f)
    closet.register(:a) { "x" }
    expect(closet.resolve(:f)).to eql("xbcdef")
  end

  it "resets the dependency tree on reregister" do
    closet.register(:a) { "a" }
    closet.register(:b1) {|c| c.a + "b1" }
    closet.register(:b2) {|c| c.a + "b2" }
    closet.register(:c) {|c| c.b1 + c.b2 + "c" }
    closet.resolve(:c)
    closet.register(:a) { "x" }
    expect(closet.resolve(:c)).to eql("xb1xb2c")
  end

  it "allows nesting" do
    closet.register(:a) { "a" }
    closet.register(:b) {|c| c.a + "b" }
    closet.register(:c) {|c| c.b + "c" }
    expect(closet.resolve(:c)).to eql("abc")
  end

  it "ignores order" do
    closet.register(:c) {|c| c.b + "c" }
    closet.register(:b) {|c| c.a + "b" }
    closet.register(:a) { "a" }
    expect(closet.resolve(:c)).to eql("abc")
  end
end
