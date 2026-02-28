module ConsoleAgent
  class SessionsController < ApplicationController
    def index
      @sessions = Session.recent.limit(100)
    end

    def show
      @session = Session.find(params[:id])
      @conversation = begin
        JSON.parse(@session.conversation)
      rescue
        []
      end
    end
  end
end
