require 'sinatra'
require 'sinatra/cors'
require 'ruby/openai'

OpenAI.configure do |config|
  config.access_token    = ENV.fetch('OPENAI_ACCESS_TOKEN')
  config.organization_id = ENV.fetch('OPENAI_ORGANIZATION') # Optional.
end

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || "8080"

set :allow_origin,   'https://gpt-linter.onrender.com http://localhost:8080'
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

def get_few_shot
  <<-HINT_FOR_AI
  As a AI Mentor you are checking Japanese sentences on a project proposed by young creator who are willing to apply Mitou Junior program. Do the following step by step:

  1. Praise their work first in your words.
  2. Show a few ideas that they can do to make the sentences more explicitly.
  3. Give one example sentence that follows the ideas but keep their taste remain and never modify their project for their creativity.

  The following is user's input. Your output should be in Japanese, started with '# AI からの文章フィードバック', and formatted in Markdown.


  HINT_FOR_AI
end

def chat_gpt_request(user_query)
  few_shot = get_few_shot()
  client   = OpenAI::Client.new
  response = client.chat(
                    parameters: {
                           model:  "gpt-3.5-turbo",
                           messages: [
                             {
                               role: "user",
                               content: few_shot + user_query,
                             }
                           ],
                           temperature: 0.7,
                           #stream: True,
                         }
                    )

  response.dig("choices", 0, "message", "content")
end
