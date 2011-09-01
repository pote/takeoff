require 'rubygems'
require 'sinatra/base'
require 'json'
require 'nokogiri'
require 'fileutils'

here = File.expand_path(File.dirname(__FILE__))
require "#{here}/takeoff_utils"
require "#{here}/princely"

begin
  require 'RMagick'
rescue LoadError
  $stderr.puts 'image sizing disabled - install rmagick'
end

begin
  require 'pdfkit'
rescue LoadError
  $stderr.puts 'pdf generation disabled - install pdfkit'
end

begin
  require 'rdiscount'
rescue LoadError
  require 'bluecloth'
  Object.send(:remove_const,:Markdown)
  Markdown = BlueCloth
end

begin
  require 'airplay'
rescue LoadError
  $stderr.puts 'Apple TV airplay streaming disabled - install airplay gem'
end
require 'pp'

class TakeOff < Sinatra::Application

  Version = VERSION = '0.5.0'

  attr_reader :cached_image_size

  set :views, File.dirname(__FILE__) + '/../views'
  set :public, File.dirname(__FILE__) + '/../public'

  def initialize(app=nil)
    super(app)
    takeoff_dir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    if Dir.pwd == takeoff_dir
      options.pres_dir = "#{takeoff_dir}/example"
      @root_path = "."
    else
      options.pres_dir ||= Dir.pwd
      @root_path = ".."
    end
    options.pres_dir = File.expand_path(options.pres_dir)
    if (options.pres_file)
      puts "Using #{options.pres_file}"
      TakeOFfUtils.presentation_config_file = options.pres_file
    end
    puts "Serving presentation from #{options.pres_dir}"

    @cached_image_size = {}
    @pres_name = options.pres_dir.split('/').pop
    require_ruby_files

    if defined?(Airplay)
      @presentation_path = options.pres_dir
      @airplay = Airplay::Client.new
      $stderr.puts "Using Airplay Server \"#{ @airplay.active_server.name }\" (#{ @airplay.active_server.ip })"
    end
  end

  def require_ruby_files
    Dir.glob("#{options.pres_dir}/*.rb").map { |path| require path }
  end

  helpers do
    def load_section_files(section)
      section = File.join(options.pres_dir, section)
      files = if File.directory? section
        Dir.glob("#{section}/**/*").sort
      else
        [section]
      end
      pp files
      files
    end

    def css_files
      Dir.glob("#{options.pres_dir}/*.css").map { |path| File.basename(path) }
    end

    def js_files
      Dir.glob("#{options.pres_dir}/*.js").map { |path| File.basename(path) }
    end


    def preshow_files
      Dir.glob("#{options.pres_dir}/_preshow/*").map { |path| File.basename(path) }.to_json
    end

    # todo: move more behavior into this class
    class Slide
      attr_reader :classes, :text
      def initialize classes = ""
        @classes = ["content"] + classes.strip.chomp('>').split
        @text = ""
      end
      def <<(s)
        @text << s
        @text << "\n"
      end
      def empty?
        @text.strip == ""
      end
    end


    def process_markdown(name, content, static=false, pdf=false)

      # if there are no !SLIDE markers, then make every H1 define a new slide
      unless content =~ /^\<?!SLIDE/m
        content = content.gsub(/^# /m, "<!SLIDE>\n# ")
      end

      # todo: unit test
      lines = content.split("\n")
      puts "#{name}: #{lines.length} lines"
      slides = []
      slides << (slide = Slide.new)
      until lines.empty?
        line = lines.shift
        if line =~ /^<?!SLIDE(.*)>?/
          slides << (slide = Slide.new($1))
        elsif line =~ /^# / && !slide.empty?
          # every H1 defines a new slide, unless there's a !SLIDE before it
          # todo: make this a CL option
          # todo: unit test
          slides << (slide = Slide.new())
          slide << line
        else
          slide << line
        end
      end

      slides.delete_if {|slide| slide.empty? }

      final = ''
      if slides.size > 1
        seq = 1
      end
      slides.each do |slide|
        md = ''
        content_classes = slide.classes

        # extract transition, defaulting to none
        transition = 'none'
        content_classes.delete_if { |x| x =~ /^transition=(.+)/ && transition = $1 }
        # extract id, defaulting to none
        id = nil
        content_classes.delete_if { |x| x =~ /^#([\w-]+)/ && id = $1 }
        # create html
        md += "<div"
        md += " id=\"#{id}\"" if id
        md += " class=\"slide\" data-transition=\"#{transition}\">"
        if seq
          md += "<div class=\"#{content_classes.join(' ')}\" ref=\"#{name}/#{seq.to_s}\">\n"
          seq += 1
        else
          md += "<div class=\"#{content_classes.join(' ')}\" ref=\"#{name}\">\n"
        end
        sl = Markdown.new(slide.text).to_html
        sl = update_image_paths(name, sl, static, pdf)
        md += sl
        md += "</div>\n"
        md += "</div>\n"
        final += update_commandline_code(md)
        final = update_p_classes(final)
      end
      final
    end

    # find any lines that start with a <p>.(something) and turn them into <p class="something">
    def update_p_classes(markdown)
      markdown.gsub(/<p>\.(.*?) /, '<p class="\1">')
    end

    def update_image_paths(path, slide, static=false, pdf=false)
      paths = path.split('/')
      paths.pop
      path = paths.join('/')
      replacement_prefix = static ?
        ( pdf ? %(img src="file://#{options.pres_dir}/#{path}) : %(img src="./file/#{path}) ) :
        %(img src="/image/#{path})
      slide.gsub(/img src=\"(.*?)\"/) do |s|
        img_path = File.join(path, $1)
        w, h     = get_image_size(img_path)
        src      = %(#{replacement_prefix}/#{$1}")
        if w && h
          src << %( width="#{w}" height="#{h}")
        end
        src
      end
    end

    if defined?(Magick)
      def get_image_size(path)
        if !cached_image_size.key?(path)
          img = Magick::Image.ping(path).first
          cached_image_size[path] = [img.columns, img.rows]
        end
        cached_image_size[path]
      end
    else
      def get_image_size(path)
      end
    end

    def update_commandline_code(slide)
      html = Nokogiri::XML.parse(slide)

      html.css('pre').each do |pre|
        pre.css('code').each do |code|
          out = code.text
          lines = out.split("\n")
          if lines.first.strip[0, 3] == '@@@'
            lang = lines.shift.gsub('@@@', '').strip
            pre.set_attribute('class', 'sh_' + lang.downcase)
            code.content = lines.join("\n")
          end
        end
      end

      html.css('.commandline > pre > code').each do |code|
        out = code.text
        lines = out.split(/^\$(.*?)$/)
        lines.delete('')
        code.content = ''
        while(lines.size > 0) do
          command = lines.shift
          result = lines.shift
          c = Nokogiri::XML::Node.new('code', html)
          c.set_attribute('class', 'command')
          c.content = '$' + command
          code << c
          c = Nokogiri::XML::Node.new('code', html)
          c.set_attribute('class', 'result')
          c.content = result
          code << c
        end
      end
      html.root.to_s
    end

    def get_slides_html(static=false, pdf=false)
      sections = TakeOffUtils.takeoff_sections(options.pres_dir)
      if sections
        data = ''
        sections.each do |section|
          if section =~ /^#/
            name = section.each_line.first.gsub(/^#*/,'').strip
            data << process_markdown(name, "<!SLIDE subsection>\n" + section, static, pdf)
          else
            files = []
            files << load_section_files(section)
            files = files.flatten
            files = files.select { |f| f =~ /.md/ }
            files.each do |f|
              fname = f.gsub(options.pres_dir + '/', '').gsub('.md', '')
              data << process_markdown(fname, File.read(f), static, pdf)
            end
          end
        end
      end
      data
    end

    def inline_css(csses, pre = nil)
      css_content = '<style type="text/css">'
      csses.each do |css_file|
        if pre
          css_file = File.join(File.dirname(__FILE__), '..', pre, css_file)
        else
          css_file = File.join(options.pres_dir, css_file)
        end
        css_content += File.read(css_file)
      end
      css_content += '</style>'
      css_content
    end

    def inline_js(jses, pre = nil)
      js_content = '<script type="text/javascript">'
      jses.each do |js_file|
        if pre
          js_file = File.join(File.dirname(__FILE__), '..', pre, js_file)
        else
          js_file = File.join(options.pres_dir, js_file)
        end
        js_content += File.read(js_file)
      end
      js_content += '</script>'
      js_content
    end

    def inline_all_js(jses_directory)
       inline_js(Dir.entries(File.join(File.dirname(__FILE__), '..', jses_directory)).find_all{|filename| filename.length > 2 }, jses_directory)
    end

    def index(static=false)
      if static
        @title = TakeOffUtils.takeoff_title
        @slides = get_slides_html(static)
        @asset_path = "./"
      end
      erb :index
    end

    def clean_link(href)
      if href && href[0, 1] == '/'
        href = href[1, href.size]
      end
      href
    end

    def assets_needed
      assets = ["index", "slides"]

      index = erb :index
      html = Nokogiri::XML.parse(index)
      html.css('head link').each do |link|
        href = clean_link(link['href'])
        assets << href if href
      end
      html.css('head script').each do |link|
        href = clean_link(link['src'])
        assets << href if href
      end

      slides = get_slides_html
      html = Nokogiri::XML.parse("<slides>" + slides + "</slides>")
      html.css('img').each do |link|
        href = clean_link(link['src'])
        assets << href if href
      end

      css = Dir.glob("#{options.public}/**/*.css").map { |path| path.gsub(options.public + '/', '') }
      assets << css

      js = Dir.glob("#{options.public}/**/*.js").map { |path| path.gsub(options.public + '/', '') }
      assets << js

      assets.uniq.join("\n")
    end

    def slides(static=false)
      get_slides_html(static)
    end

    def onepage(static=false)
      @slides = get_slides_html(static)
      erb :onepage
    end

    def pdf(static=true)
      @slides = get_slides_html(static, true)
      @no_js = false
      html = erb :onepage
      # TODO make a random filename

      # PDFKit.new takes the HTML and any options for wkhtmltopdf
      # run `wkhtmltopdf --extended-help` for a full list of options
      kit = PDFKit.new(html, :page_size => 'Letter', :orientation => 'Landscape')

      # Save the PDF to a file
      file = kit.to_file('/tmp/preso.pdf')
    end
  end


   def self.do_static(what)
      what = "index" if !what

      # Nasty hack to get the actual TakeOff module
      takeoff = TakeOff.new
      while !takeoff.is_a?(TakeOff)
        takeoff = takeoff.instance_variable_get(:@app)
      end
      name = takeoff.instance_variable_get(:@pres_name)
      path = takeoff.instance_variable_get(:@root_path)
      data = takeoff.send(what, true)
      if data.is_a?(File)
        FileUtils.cp(data.path, "#{name}.pdf")
      else
        out  = "#{path}/#{name}/static"
        # First make a directory
        FileUtils.makedirs(out)
        # Then write the html
        file = File.new("#{out}/index.html", "w")
        file.puts(data)
        file.close
        # Now copy all the js and css
        my_path = File.join( File.dirname(__FILE__), '..', 'public')
        ["js", "css"].each { |dir|
          FileUtils.copy_entry("#{my_path}/#{dir}", "#{out}/#{dir}")
        }
        # And copy the directory
        Dir.glob("#{my_path}/#{name}/*").each { |subpath|
          base = File.basename(subpath)
          next if "static" == base
          next unless File.directory?(subpath) || base.match(/\.(css|js)$/)
          FileUtils.copy_entry(subpath, "#{out}/#{base}")
        }

        # Set up file dir
        file_dir = File.join(out, 'file')
        FileUtils.makedirs(file_dir)
        pres_dir = takeoff.options.pres_dir

        # ..., copy all user-defined styles and javascript files
        Dir.glob("#{pres_dir}/*.{css,js}").each { |path|
          FileUtils.copy(path, File.join(file_dir, File.basename(path)))
        }

        # ... and copy all needed image files
        data.scan(/img src=\".\/file\/(.*?)\"/).flatten.each do |path|
          dir = File.dirname(path)
          FileUtils.makedirs(File.join(file_dir, dir))
          FileUtils.copy(File.join(pres_dir, path), File.join(file_dir, path))
        end
        # copy images from css too
        Dir.glob("#{pres_dir}/*.css").each do |css_path|
          File.open(css_path) do |file|
            data = file.read
            data.scan(/url\((.*)\)/).flatten.each do |path|
              p path
              dir = File.dirname(path)
              FileUtils.makedirs(File.join(file_dir, dir))
              FileUtils.copy(File.join(pres_dir, path), File.join(file_dir, path))
            end
          end
        end
      end
    end

   def eval_ruby code
     eval(code).to_s
   rescue => e
     e.message
   end

   put '/airplay' do
     slide = params[:slide]
     puts "Received airplay stream request for slide #{ slide }"

     if !FileTest.exists? "#{ @presentation_path }/png/#{ slide }-full.png"
       puts "Generating png version of slide #{ slide }, storing into #{ @presentation_path }/png"
       %x[ webkit2png -F http://0.0.0.0:9090/##{ slide } -o #{ @presentation_path }/png/#{ slide }]
     end

     @airplay.send_image "#{ @presentation_path }/png/#{ slide }-full.png"
   end

   post '/airplay' do
     puts "Preparing all Airplay slides - be patient"
     slides = params[:slides]
     slides.to_i.times do |slide|
       puts "Generating png version of slide #{ slide }, storing into #{ @presentation_path }/png"
       %x[webkit2png -F http://0.0.0.0:9090/##{ slide } -o #{ @presentation_path }/png/#{ slide }]
     end
   end

  get '/eval_ruby' do
    return eval_ruby(params[:code]) if ENV['TAKEOFF_EVAL_RUBY']

    return "Ruby Evaluation is off. To turn it on set ENV['TAKEOFF_EVAL_RUBY']"
  end

  get %r{(?:image|file)/(.*)} do
    path = params[:captures].first
    full_path = File.join(options.pres_dir, path)
    send_file full_path
  end

  get %r{/(.*)} do
    @title = TakeOffUtils.takeoff_title
    what = params[:captures].first
    what = 'index' if "" == what
    if (what != "favicon.ico")
      data = send(what)
      if data.is_a?(File)
        send_file data.path
      else
        data
      end
    end
  end
end
