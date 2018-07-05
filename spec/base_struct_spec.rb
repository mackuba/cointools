require 'spec_helper'

describe CoinTools::BaseStruct do
  context 'created with a list of fields' do
    let(:struct) { CoinTools::BaseStruct.make(:one, :two, :z) }

    it 'should be a subclass of CoinTools::BaseStruct' do
      struct.should be_a(Class)
      struct.superclass.should == CoinTools::BaseStruct
    end

    it 'should have all defined fields' do
      instance = struct.new(two: 1, one: 2, z: 'a')
      instance.one.should == 2
      instance.two.should == 1
      instance.z.should == 'a'
    end
  end
end
