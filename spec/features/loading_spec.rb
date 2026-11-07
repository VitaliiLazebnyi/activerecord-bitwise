# typed: false
# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'Loading the gem' do
  let(:library_path) { File.expand_path('../../lib', __dir__) }
  let(:load_script) { "require 'activerecord-bitwise'; print ActiveRecord::Bitwise::VERSION" }
  let(:outcome) { Open3.capture3(RbConfig.ruby, '-I', library_path, '-e', load_script) }

  it 'succeeds in a fresh process that has not loaded sorbet-runtime before' do
    expect(outcome.last).to be_success
  end

  it 'makes the version available' do
    expect(outcome.first).to eq(ActiveRecord::Bitwise::VERSION)
  end

  it 'teaches every ActiveRecord model the bitwise macro' do
    expect(ActiveRecord::Base).to respond_to(:bitwise)
  end

  it 'registers the bitwise validator' do
    expect(BitwiseValidator).to be < ActiveModel::EachValidator
  end
end
