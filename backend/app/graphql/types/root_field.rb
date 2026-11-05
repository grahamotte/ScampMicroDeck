module Types
  class RootField < BaseField
    def initialize(*args, access:, **kwargs, &block)
      super(*args, access:, **kwargs, &block)
    end
  end
end
