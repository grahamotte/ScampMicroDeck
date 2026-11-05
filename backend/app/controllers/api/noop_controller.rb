module Api
  class NoopController < ApplicationController
    def ping
      render json: { message: "pong" }
    end
  end
end
