Rails.application.routes.draw do
  post '/aeon/aeon-request-popup', to: 'aeon_request#popup'
end
