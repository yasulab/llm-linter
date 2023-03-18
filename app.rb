require 'sinatra'
require 'sinatra/cors'
require 'ruby/openai'

OpenAI.configure do |config|
  config.access_token    = ENV.fetch('OPENAI_ACCESS_TOKEN')
  config.organization_id = ENV.fetch('OPENAI_ORGANIZATION') # Optional.
end

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || "8080"

set :allow_origin,   'https://gpt-linter.onrender.com'
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
  You are a tutor that checks Japanese sentences on a project proposed by young creator who are willing to apply "未踏ジュニア" program. Do the following step by step:

  1. Praise their work first in your words.
  2. Show a few ideas that they can do to make the sentences more explicitly.
  3. Give one example sentence that follows the ideas but keep their taste remain and never modify their project for their creativity.

  The following is user's input. Your output should be casual in Japanese, started with '# AI からの文章フィードバック', and formatted in Markdown.


  HINT_FOR_AI
end

def failed_no_inputs_given; "# AI からの文章フィードバック\n\n未踏ジュニアに興味を持っていただきありがとうございます！私は提案書の概要や、提案書の文章をチェックする AI です。\n\n「サンプル文章を入力する」ボタンを押してから、「AI の文章をみてもらう」ボタンを押すと、私の回答例を確認できます。ぜひ試してみてくださいね！" end
def failed_longer_than_500; "# AI からの文章フィードバック\n\nすみません！私が一度に見れる文章は500文字までとなります。500文字以内に区切ってから、再度「AI の文章をみてもらう」ボタンを押していただけると嬉しいです。" end

def chat_gpt_request(user_query)
  return failed_no_inputs_given if user_query.size == 0
  return failed_longer_than_500 if user_query.size > 500
  prompt   = get_prompt()
  client   = OpenAI::Client.new
  response = client.chat(
                    parameters: {
                           # https://platform.openai.com/docs/models/gpt-4
                           #model:  'gpt-3.5-turbo',
                           model:  'gpt-4',
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
                    )

  response.dig('choices', 0, 'message', 'content')
end

