Rails.application.routes.draw do
  post '/aeon/aeon-request-popup', to: 'aeon_request#popup'
  post '/aeon/aeon-request-build', to: 'aeon_request#build'

  get '/plugin/yale_aeon_mappings/inline_aeon_request_form', to: 'inline_aeon_request#form'
end
