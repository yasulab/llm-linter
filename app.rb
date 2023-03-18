require 'sinatra'
require 'sinatra/cors'
require 'ruby/openai'

OpenAI.configure do |config|
  config.access_token    = ENV.fetch('OPENAI_ACCESS_TOKEN')
  config.organization_id = ENV.fetch('OPENAI_ORGANIZATION') # Optional.
end

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || "8080"

set :allow_origin,   "https://gpt-linter.onrender.com #{ENV['SINATRA_LOCALHOST']}".rstrip
set :allow_methods,  'GET,HEAD,POST'
set :allow_headers,  'content-type,if-modified-since'
set :expose_headers, 'location,link'

get '/' do
  erb :index
end

post '/gpt' do
  input_text = params[:input_text]
  response   = chat_gpt_request(input_text)

  content_type :json
  { response: response }.to_json
end

def get_prompt
  <<-HINT_FOR_AI
  You are a tutor that feedbacks on a abstract of project, called "概要文", proposed by young creator who are willing to apply "未踏ジュニア" program. The abstract has to be within 200 words in Japanese.

  Show a few ideas that they may make it more attractive but keep their taste remain and *never* modify their project for their creativity. Keep in mind that the 200 words is too short to follow all of your ideas.

  Output has to be *a suggestion* in Japanese, *never* show your example, started with '# AI によるコメント', and formatted in Markdown. Show your understand of a project and start your comment from "私の理解が正しければ". Also make sure to note the possibility that their abstract may be already perfect enough, nothing has to be changed.


  HINT_FOR_AI
end

def failed_no_inputs_given; "# AI からのコメント\n\n未踏ジュニアに興味を持っていただきありがとうございます！私は提案書の概要文にコメントをする実験的な AI です。(非公式)\n\n「サンプル概要文を入力する」ボタンを押してから、「AI に概要文を見てもらう」ボタンを押すと、私のコメントを確認できます。ぜひ試してみてくださいね！" end
def failed_longer_than_200; "# AI からのコメント\n\nすみません！概要文は200文字以内となります。200文字以内に収めてから、再度「AI の文章をみてもらう」ボタンを押していただけると嬉しいです。" end
def failed_after_deadline;  "# AI からのコメント\n\nすみません！2023年度の未踏ジュニア応募〆切は2023年4月8日 23:59 までとなるため、それに伴って実験的な本システムの提供も終了いたしました。\n\nあらためて、未踏ジュニアに興味を持っていただきありがとうございました！" end

def is_after_deadline?
  t1 = Time.new(2023, 4, 8, 23, 59, 59, "+09:00")
  t2 = Time.now.localtime("+09:00")
  p(t2)
  t1 < t2
end

def chat_gpt_request(user_query)
  return failed_no_inputs_given if user_query.size == 0
  return failed_longer_than_200 if user_query.size > 200
  return failed_after_deadline  if is_after_deadline?

  prompt = get_prompt()
  client = OpenAI::Client.new
  model  = 'gpt-4'
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
  response = client.chat(parameters: params)

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
  else
    # Expenses on GPT-3.5-turbo: https://openai.com/pricing
    p_expenses = (p_tokens * 0.002 / 1000) # dollars
    c_expenses = (c_tokens * 0.002 / 1000) # dollars
    puts "Prmpt Tokens: #{p_tokens} (#{(p_expenses).to_yen.floor(2)}円)"
    puts "Cmplt Tokens: #{c_tokens} (#{(c_expenses).to_yen.floor(2)}円)"
    puts "掛かった料金: #{(p_expenses + c_expenses).to_yen.floor(2)}円"
  end
  puts "使ったモデル: " + model

  response.dig('choices', 0, 'message', 'content')
end

class Float
  def to_yen; self * 135; end
end

