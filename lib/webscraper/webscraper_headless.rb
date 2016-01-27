require 'headless'
require 'user_agent_randomizer'
require_relative '../error'
require_relative '../parameter'
module Webscrapers

  class WebscraperHeadless < Webscraper
    include Errors


    def self.build(geolocation)
      case os
        when :linux, :unix
          WebscraperHeadlessXvfb.new(geolocation)

        when :windows
          WebscraperHeadlessPhantomjs.new(geolocation)
      end
    end

    private
    def self.os
      host_os = RbConfig::CONFIG['host_os']
      case host_os
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          :windows
        when /darwin|mac os/
          :macosx
        when /linux/
          :linux
        when /solaris|bsd/
          :unix
        else
          raise Error.new(UNKNOWN_OS, :values => {:os => host_os})

      end
    end
  end

  class WebscraperHeadlessPhantomjs < WebscraperHeadless
    #TODO se reposer la question de l'interet d'utiliser phanomjs et de donc de conserver un webdriver headless qui le met en oeuvre
    MAX_COUNT_WEBSCRAPER = 5
    START_LISTENING_PORT_PHANTOMJS = 10001


    # liste des port d'écoute phantomjs non utilisé
    @@listening_port_phantomjs_free = Array.new(MAX_COUNT_WEBSCRAPER) { |i| START_LISTENING_PORT_PHANTOMJS + i }
    # liste des port d'écoute phantomjs utilisé
    @@listening_port_phantomjs_busy = []
    #protection des maj des variable de class
    @@sem = Mutex.new

    attr :path_phantomjs, # path du runtime phantomjs
         :listening_port_phantomjs, #port découte de de l'instance courante de phantomjs
         :pid_phantomjs, #pid phantomjs
         :cookies_file #file contenant les cookies de l'instance courante du phantomjs

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
        @path_phantomjs = parameters.path_phantomjs
      end

      raise "phantomjs runtime not found" unless File.exist?(@path_phantomjs.join(File::SEPARATOR))
      book_listening_port
      @cookies_file = [TMP, "phantomjs_#{@listening_port_phantomjs}_cookies_file.txt"].join(File::SEPARATOR)
      File.delete(@cookies_file) if File.exist?(@cookies_file)

    end

    def navigate_to(url)
      begin
        @driver.navigate.to url

      rescue Exception => e
        raise Error.new(NAVIGATE_FAILED, :values => {:url => url}, :error => e)

      else
        raise Error.new(URL_UNREACHABLE, :values => {:url => url}) if @driver.page_source.include?("loadError.label") #phantomjs

      end

    end

    def start
      begin
        cmd = "#{@path_phantomjs.join(File::SEPARATOR)}"
        cmd += " --webdriver=#{@listening_port_phantomjs}"
        cmd += " --disk-cache=false"
        cmd += " --ignore-ssl-errors=true"
        cmd += " --load-images=false"
        cmd += " --cookies-file=#{@cookies_file}"
        cmd += " --remote-debugger-autorun=yes"
        cmd += " --remote-debugger-port=#{@listening_port_phantomjs + 5000}" #TODO confirmer le besoin

        unless @geolocation.nil?
          cmd += " --proxy=#{@geolocation.ip}:#{@geolocation.port}"
          cmd += " --proxy-auth=#{@geolocation.user}:#{@geolocation.password}" unless @geolocation.user.empty?
          cmd += " --proxy-type=#{@geolocation.protocol}"
        end

        @pid_phantomjs = Process.spawn(cmd)

      rescue Exception => e
        raise Error.new(PHANTOMJS_NOT_START, :error => e)

      end

      sleep 5

      begin
        #mettre un user agent dont on connait le comportement google
        @user_agent = UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string
        capabilities = Selenium::WebDriver::Remote::Capabilities.phantomjs("phantomjs.page.settings.userAgent" => @user_agent)
        client = Selenium::WebDriver::Remote::Http::Default.new
        client.timeout = 120 # seconds
        @driver = Selenium::WebDriver.for :phantomjs,
                                          :url => "http://localhost:#{@listening_port_phantomjs}",
                                          :desired_capabilities => capabilities,
                                          :http_client => client
        @driver.manage.timeouts.implicit_wait = 3
      rescue Exception => e
        raise Error.new(DRIVER_NOT_START, :error => e)

      end
    end

    def stop
      begin
        @driver.quit

      rescue Exception => e
        raise Error.new(DRIVER_NOT_STOP, :error => e)

      ensure
        Process.kill("KILL", @pid_phantomjs)
        File.delete(@cookies_file) if File.exist?(@cookies_file)

        free_listening_port
      end
    end

    def to_s
      "headless : phantomjs, geolocation : #{@geolocation.nil? ? "none" : @geolocation}"
    end

    private
    def book_listening_port
      @@sem.synchronize {
        raise Error.new(NO_FREE_PHANTOMJS) if @@listening_port_phantomjs_free.size == 0

        @listening_port_phantomjs = @@listening_port_phantomjs_free.shift

        @@listening_port_phantomjs_busy << @listening_port_phantomjs

      }
    end

    def free_listening_port
      @@sem.synchronize {
        @@listening_port_phantomjs_busy.delete(@listening_port_phantomjs)

        @@listening_port_phantomjs_free << @listening_port_phantomjs
      }
    end

    private
    def take_screenshot
      #TODO
    end
  end

  class WebscraperHeadlessXvfb < WebscraperHeadless

    attr :headless # utiliser pour supprimer la gui pour firefox sous linux

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
        Headless::CliUtil.ensure_application_exists!("firefox", "firefox not found")
        @path_firefox = Headless::CliUtil.path_to("firefox")
      end


    end

    def navigate_to(url)
      begin
        @driver.navigate.to url

      rescue Exception => e
        raise Error.new(NAVIGATE_FAILED, :values => {:url => url}, :error => e)

      else
        raise Error.new(URL_UNREACHABLE, :values => {:url => url}) if @driver.page_source == "<html><head></head><body></body></html>" # firefox with xfvb

      end

    end

    def start
      begin
        # sous linux utilisation de xfvb pour lancer le webdriver headless
        @headless = Headless.new(reuse: false, destroy_at_exit: true)
        @headless.start

      rescue Exception => e
        raise Error.new(XVFB_NOT_START, :error => e)

      end

      begin
        start_firefox

      rescue Exception => e
        @headless.stop
        raise Error.new(DRIVER_NOT_START, :error => e)

      end

    end

    def stop
      count = 10
      logger = Logging::Log.new(self, :staging => $staging, :id_file => File.basename(__FILE__, ".rb"), :debugging => $debugging)
      begin
        @driver.quit

      rescue Exception => e
        count -= 1
        logger.an_event.warn "#{count} try to stop webdriver "
        sleep 1
        retry if count > 0
        #raise Error.new(DRIVER_NOT_STOP, :error => e)
        logger.an_event.error "dont stop webdriver #{e}"
        logger.an_event.debug e
      ensure
        @headless.destroy

      end

    end

    def to_s
      "headless : xfvb(display=#{@headless.display}), geolocation : #{@geolocation.nil? ? "none" : @geolocation}"
    end

    private
    def take_screenshot
      file = File.expand_path(File.join("..", "..", "..", "log", "screenshot_#{Time.now.strftime("%Y%m%dT%H%M")}"), __FILE__) + ".jpeg"
      @headless.take_screenshot(file)
    end
  end
end
