Rails.application.routes.draw do
  post '/aeon/aeon-request-popup', to: 'aeon_request#popup'
  post '/aeon/aeon-request-build', to: 'aeon_request#build'
end
