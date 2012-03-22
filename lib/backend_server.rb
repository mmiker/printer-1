require "rubygems"
require "bundler/setup"
require "sinatra"
require 'sinatra/base'
require "resque"

require "jobs"
require "printer"
require "preview"

class WeePrinterBackendServer < Sinatra::Base
  set :views, settings.root + '/../views'
  set :public_folder, settings.root + '/../public'

  get "/" do
    erb :index
  end

  get("/getting-a-wee-printer") { erb :getting_a_wee_printer }
  get("/api") { erb :api }
  get("/publishing") { erb :publishing }

  get "/preview/show/:preview_id" do
    @preview = Preview.find(params['preview_id'])
    erb :preview
  end

  get "/preview/pending/:preview_id" do
    preview = Preview.find(params['preview_id'])
    if preview
      redirect "/preview/show/#{params['preview_id']}"
    else
      erb :preview_pending
    end
  end

  get "/preview" do
    queue_preview(params['url'] || env['HTTP_REFERER'])
  end

  post "/preview" do
    if params['content']
      queue_preview_from_content(params['content'])
    else
      queue_preview(params['url'])
    end
  end

  get "/print/:printer_id" do
    queue_print(params['printer_id'], params['url'] || env['HTTP_REFERER'])
  end

  post "/print/:printer_id" do
    if params['content']
      queue_print_from_content(params['printer_id'], params['content'])
    else
      queue_print(params['printer_id'], params['url'])
    end
  end

  get "/printer/:printer_id" do
    Printer.new(params['printer_id']).archive_and_return_print_data
  end

  get "/test/fixed/:length" do
    "#" * params['length'].to_i
  end

  get "/test/between/:min/:max" do
    min = params['min'].to_i
    max = params['max'].to_i
    length = rand(max-min) + min
    "#" * length
  end

  get "/test/maybe" do
    if rand(10) > 7
      "#" * (rand(100000) + 20000)
    end
  end

  private

  def queue_print(printer_id, url)
    Resque.enqueue(Jobs::PreparePage, printer_id, url)
    erb :queued
  end

  def queue_preview(url)
    preview_id = (0..16).map { |x| rand(16).to_s(16) }.join
    Resque.enqueue(Jobs::Preview, preview_id, url)
    redirect "/preview/pending/#{preview_id}"
  end

  def queue_print_from_content(printer_id, content)
    Resque.enqueue(Jobs::PrepareContent, printer_id, content)
    if request.accept?('application/json')
      headers "Access-Control-Allow-Origin" => "*"
      content_type :json
      MultiJson.encode({response: "ok"})
    else
      erb :queued
    end
  end

  def queue_preview_from_content(content)
    preview_id = (0..16).map { |x| rand(16).to_s(16) }.join
    Resque.enqueue(Jobs::PreviewContent, preview_id, content)
    path = "/preview/pending/#{preview_id}"
    if request.accept?('application/json')
      headers "Access-Control-Allow-Origin" => "*"
      content_type :json
      url = request.scheme + "://" + request.host_with_port + path
      MultiJson.encode({location: url})
    else
     redirect path
    end
  end
end