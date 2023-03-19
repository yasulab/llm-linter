require 'sinatra'
require 'sinatra/cors'
require 'sinatra/reloader' if ENV['SINATRA_LOCALHOST']
require 'ruby/openai'
require 'cgi'

OpenAI.configure do |config|
  config.access_token    = ENV.fetch('OPENAI_ACCESS_TOKEN')
  config.organization_id = ENV.fetch('OPENAI_ORGANIZATION') # Optional.
  config.request_timeout = 180 # 60 by default.
  # Grabing this PR from fork repo: https://github.com/alexrudall/ruby-openai/pull/192
end

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || "8080"

set :allow_origin,   "https://gpt-linter.onrender.com #{ENV['SINATRA_LOCALHOST']}".rstrip
set :allow_methods,  'GET,HEAD,POST'
set :allow_headers,  'content-type,if-modified-since'
set :expose_headers, 'location,link'

get '/'       do; erb :index;  end
get '/policy' do; erb :policy; end
get '/terms'  do; erb :terms;  end

post '/gpt' do
  input_text = params[:input_text]
  response   = chat_gpt_request(input_text)

  content_type :json
  { response: response }.to_json
end

post '/reaction' do
  reaction = params[:reaction]
  puts "Reaction: #{reaction}"
  { status: 'success' }.to_json
end

def get_prompt
  <<-HINT_FOR_AI
  You are a tutor that feedbacks on a abstract of project, called "概要文", proposed by young creator who are willing to apply "未踏ジュニア" program. The abstract has to be within 200 words in Japanese.

  Output has to be Japanese, started with '# AI によるコメント', formatted in Markdown, and *never* use HTML in it. Then, start your comment step by step:

  1. Praise their work in your words.
  2. Show your understanding on the project, started from "私の理解が正しければ".
  3. Show a few ideas that they may make their abstract more attractive but keep their taste remain and strongly respect their creativity. It means that *never* modify their project, *never* show your example, and *never* add a feature.

  Keep in mind that the 200 words are too short to follow all of your ideas. Also make sure to note that their abstract may be already perfect enough and nothing has to be changed.


  HINT_FOR_AI
end

def failed_no_inputs_given; "# AI からのコメント\n\n未踏ジュニアに興味を持っていただきありがとうございます！私は提案書の概要文にコメントをする実験的な AI です。(非公式)\n\n「サンプル概要文を入力する」ボタンを押してから、「AI に概要文を見てもらう」ボタンを押すと、私のコメントを確認できます。ぜひ試してみてくださいね！" end
def failed_longer_than_200; "# AI からのコメント\n\nすみません！概要文は200文字以内となります。200文字以内に収めてから、再度「AI の文章をみてもらう」ボタンを押していただけると嬉しいです。" end
def failed_after_deadline;  "# AI からのコメント\n\nすみません！2023年度の未踏ジュニア応募〆切は2023年4月8日 23:59 までとなるため、それに伴って実験的な本システムの提供も終了いたしました。\n\nあらためて、未踏ジュニアに興味を持っていただきありがとうございました！" end
def failed_on_http_timeout;  "# AI からのコメント\n\nすみません！現在 ChatGPT へのリクエストが混み合っているようで、応答が返って来ないようです。\n\nお手数をかけてしまって申し訳ありませんが、時間を置いてから再度チャレンジしていただけると幸いです。" end
def failed_on_server_error;  "# AI からのコメント\n\nすみません！現在 ChatGPT へのリクエストが混み合っているようで、先ほどエラーが返って来ました。\n\nお手数をかけてしまって申し訳ありませんが、時間を置いてから再度チャレンジしていただけると幸いです。" end

def is_after_deadline?
  t1 = Time.new(2023, 4, 8, 23, 59, 59, "+09:00")
  t2 = Time.now.localtime("+09:00")
  puts t2
  t1 < t2
end

def chat_gpt_request(user_query)
  return failed_no_inputs_given if user_query.size == 0
  return failed_longer_than_200 if user_query.size > 200
  return failed_after_deadline  if is_after_deadline?

  prompt = get_prompt()
  client = OpenAI::Client.new
  model  = ENV['SINATRA_LOCALHOST'].nil? ? 'gpt-4' : 'gpt-3.5-turbo'
  #model  = 'gpt-4'
  #model  = 'gpt-3.5-turbo'
  params = {
    # https://platform.openai.com/docs/models/gpt-4
    model: model,
    messages: [
      {
        role: 'system',
        content: prompt,
      },
      {
        role: 'user',
        content: user_query,
      },
    ],
    temperature: 0.7,
    #stream: True,
  }

  # This may cause: Net::ReadTimeout - Net::ReadTimeout with #<TCPSocket:(closed)> error
  # Also measure how long it takes until returns result from OpenAI API.
  begin
    stt_time = Time.now
    response = client.chat(parameters: params)
    end_time = Time.now
  rescue => e
    end_time = Time.now
    puts "エラーの内容: #{e}"
    puts "掛かった時間: #{(end_time - stt_time).floor(1)}秒"
    return failed_on_http_timeout
  end
  # Return if 500 error happens for some reason
  return failed_on_server_error if response.to_s.include? "Internal Server Error"

  p_tokens = response.dig 'usage', 'prompt_tokens'
  c_tokens = response.dig 'usage', 'completion_tokens'
  t_tokens = response.dig 'usage', 'total_tokens'

  if model == 'gpt-4'
    # Expenses on GPT-4 (8K context): https://openai.com/pricing
    p_expenses = (p_tokens * 0.03 / 1000) # dollars
    c_expenses = (c_tokens * 0.06 / 1000) # dollars
    puts "Prmpt Tokens: #{p_tokens} (#{(p_expenses).to_yen.floor(2)}円)"
    puts "Cmplt Tokens: #{c_tokens} (#{(c_expenses).to_yen.floor(2)}円)"
    puts "掛かった料金: #{(p_expenses + c_expenses).to_yen.floor(2)}円"
    puts "掛かった時間: #{(end_time - stt_time).floor(0)}秒"
    puts "使ったモデル: #{model}"
  else
    # Expenses on GPT-3.5-turbo: https://openai.com/pricing
    p_expenses = (p_tokens * 0.002 / 1000) # dollars
    c_expenses = (c_tokens * 0.002 / 1000) # dollars
    puts "Prmpt Tokens: #{p_tokens} (#{(p_expenses).to_yen.floor(2)}円)"
    puts "Cmplt Tokens: #{c_tokens} (#{(c_expenses).to_yen.floor(2)}円)"
    puts "掛かった料金: #{(p_expenses + c_expenses).to_yen.floor(2)}円"
    puts "掛かった時間: #{(end_time - stt_time).floor(0)}秒"
    puts "使ったモデル: #{model}"
  end

  CGI.escapeHTML(response.dig 'choices', 0, 'message', 'content')
end

class Float
  def to_yen; self * 135; end
end
