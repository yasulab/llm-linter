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

  Output has to be *a suggestion* in Japanese, started with '# AI によるコメント', and formatted in Markdown. If you show your understanding on the input, you should start with like "My understanding of your project is ..."

  Learn how to count Japanese words by using the following examples:

  * 21 words: 自宅で手軽に筋トレができるVRソフトです。
  * 41 words: 逆方向に動く2つのキューブを同時にゴールに持っていく、シンプルなパズルゲームです。
  * 52 words: 「Visible」はNode.jsで開発されるオープンソースのWebアクセシビリティーテストツールです。

  HINT_FOR_AI
end

def failed_no_inputs_given; "# AI からの文章フィードバック\n\n未踏ジュニアに興味を持っていただきありがとうございます！私は提案書の概要や、提案書の文章をチェックする AI です。\n\n「サンプル文章を入力する」ボタンを押してから、「AI の文章をみてもらう」ボタンを押すと、私の回答例を確認できます。ぜひ試してみてくださいね！" end
def failed_longer_than_200; "# AI からの文章フィードバック\n\nすみません！概要文は200文字以内となります。200文字以内に収めてから、再度「AI の文章をみてもらう」ボタンを押していただけると嬉しいです。" end

def chat_gpt_request(user_query)
  return failed_no_inputs_given if user_query.size == 0
  return failed_longer_than_200 if user_query.size > 200
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

  p_tokens = response.dig 'usage', 'prompt_tokens'
  c_tokens = response.dig 'usage', 'completion_tokens'
  t_tokens = response.dig 'usage', 'total_tokens'
  expenses = (p_tokens * 0.03 / 1000) + (c_tokens * 0.06 / 1000) # dollars
  puts "Prmpt Tokens: " + p_tokens.to_s
  puts "Cmplt Tokens: " + c_tokens.to_s
  puts "Total Tokens: " + t_tokens.to_s
  puts "掛かった料金: " + (expenses * 135).floor(2).to_s + "円"
  response.dig('choices', 0, 'message', 'content')
end

