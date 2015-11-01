require_relative '../error'
require_relative '../parameter'
module Webscrapers
  class WebscraperGui < Webscraper
    include Errors

    def initialize(geolocation)
      super(geolocation)
      #------------------------------------------------------------------------------------------------------------------
      # PARAMETER FILE
      #--------------------------------------------------------------------------------------------------------------------
      begin
        parameters = Parameter.new("webscraper.rb")

      rescue Exception => e
        $stderr << e.message << "\n"

      else
        $staging = parameters.environment
        $debugging = parameters.debugging
        @path_firefox = parameters.path_firefox.join(File::SEPARATOR)
      end


    end


    def navigate_to(url)
      begin
        @driver.navigate.to url

      rescue Exception => e
        raise Error.new(NAVIGATE_FAILED, :values => {:url => url}, :error => e)

      else
        raise Error.new(URL_UNREACHABLE, :values => {:url => url}) if @driver.page_source == "<html><head></head><body></body></html>" # firefox with gui

      end
    end

    def start
      begin
        start_firefox

      rescue Exception => e
        raise Error.new(DRIVER_NOT_START, :error => e)

      end
    end

    def stop
      begin
        @driver.quit

      rescue Exception => e
        raise Error.new(DRIVER_NOT_STOP, :error => e)

      end

    end

    def to_s
      "with gui, geolocation : #{@geolocation.nil? ? "none" : @geolocation}"
    end

    private
    def take_screenshot
      #pas utililsé
    end
  end
end