require 'rubygems'
require 'rest_client'

url = "http://jruby-expenseit.herokuapp.com/expenses"
RestClient.delete url 
