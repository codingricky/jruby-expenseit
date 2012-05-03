require 'rubygems'
require 'json'
require 'rest_client'
require 'base64'
receipt = Base64.encode64(File.read("dius-logo.png"))

expense = {:name => 'John Smith'}
receipt_1 = {:client => 'Jemena', :category => 'Travel', :date => '24/4/2012', :amount_in_cents => 1212, :description => 'Taxi from City to SOP', :image => receipt}
receipt_2 = {:client => 'ResMed', :category => 'Travel', :date => '25/4/2012', :amount_in_cents => 9923, :description => 'Taxi from City to Bella Vista'}
expense[:receipts] = [receipt_1, receipt_2]

url = "http://jruby-expenseit.heroku.com/expense"
response = RestClient.post url, expense.to_json
puts "id=#{response}"
receipt_response = RestClient.get url + "/" + response 
json = JSON.parse(receipt_response)
image_encoded = json["receipts"].first["image"]
image_decoded = Base64.decode64(image_encoded)
File.open("downloaded-image.png", "w") {|f| f.write image_decoded}
