require 'spec_helper'

describe Slugbuilder do
  it 'has a version number' do
    expect(Slugbuilder::VERSION).not_to be nil
  end

  it 'has a configuration class' do
    expect(Slugbuilder::Configuration).not_to be nil
  end

  it 'has a builder class' do
    expect(Slugbuilder::Builder).not_to be nil
  end
end
