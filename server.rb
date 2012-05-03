require 'sinatra'
require 'json'
require 'mongo'
require 'base64'
require 'spreadsheet'
require 'jxl.jar'

DATE_COL=0
DESCRIPTION_COL=1
CLIENT_COL=2
CATEGORY_COL=3
TOTAL_COL=5

EXPENSE_START_ROW = 13

NAME_COL = 1
NAME_ROW = 9
SIGNATURE_COL = 1
SIGNATURE_ROW = 23
get '/' do
  puts "Show expenses"
  coll = get_col
  @expenses = coll.find
  erb :expenses
end

get '/hello' do
  "hello"
end

post '/expense' do
  expense = JSON.parse(request.body.read)
  coll = get_col
  id = coll.insert(expense)
  # email(id, "ricky@dius.com.au")
  
  id.to_s
end

get '/expense/:id/receipts/:index/image' do |id, index|
  coll = get_col
  
  begin
    expense = coll.find("_id" => BSON::ObjectId(id)).to_a[0]
    image_encoded = expense["receipts"][index.to_i]["image"]
    throw Exception.new unless image_encoded
    content_type "image/png"
    Base64.decode64 image_encoded
  rescue
    status 404
    "Image not found"
  end  
   
end

get '/expense' do
  coll = get_col
  expenses = coll.find.collect {|expense| expense.to_json}
   
  expenses.join
end

get '/expense/:id' do |id|
  coll = get_col
     
  begin
    coll.find("_id" => BSON::ObjectId(id)).to_a[0].to_json
  rescue
    status 404
    "Expense not found"
  end
end

delete '/expenses' do
  coll = get_col
  
  coll.remove
  coll.count.to_s
end

get '/expense/:id/excel.xls' do |id|
  send_file(generate_jruby_excel(id))  
end

post '/expense/:id/email' do |id|
  email(id, params[:emailAddress])
  "email sent to #{params[:emailAddress]}"  
end

get '/expense/:id/email/:address' do |id, address| 
  email(id, address)
  "email sent to #{address}"
end

def email(id, address)
  require 'pony'
  expense_spreadsheet = File.new(generate_jruby_excel(id))
  attachments = {"expense.xls" => expense_spreadsheet.read}
  expense = get_col.find("_id" => BSON::ObjectId(id)).to_a[0]  
  
  expense["receipts"].each_with_index do |receipt, index|
    image_encoded = receipt["image"]
    image_decoded = Base64.decode64 image_encoded
    attachments["receipt_#{index}.png"] = image_decoded
  end
  
  Pony.mail(
      :from => "testing",
      :to => address,
      :attachments => attachments,
      :subject => "Expenses",
      :body => "Please find attached my expenses",
      :port => '587',
      :via => :smtp,
      :via_options => { 
        :address              => 'smtp.sendgrid.net', 
        :port                 => '587', 
        :enable_starttls_auto => true, 
        :user_name            => ENV['SENDGRID_USERNAME'], 
        :password             => ENV['SENDGRID_PASSWORD'], 
        :authentication       => :plain, 
        :domain               => ENV['SENDGRID_DOMAIN']})

end

def generate_excel(id)
  coll = get_col
  expense = coll.find("_id" => BSON::ObjectId(id)).to_a[0]
   
   book = Spreadsheet.open("template.xls", 'r')
   sheet = book.worksheet(0)
   sheet[NAME_ROW, NAME_COL] = expense["name"]
   expense["receipts"].each_with_index do |receipt, i|
     sheet[EXPENSE_START_ROW + i, DATE_COL] = receipt["date"]
     sheet[EXPENSE_START_ROW + i, DESCRIPTION_COL] = receipt["description"]
     sheet[EXPENSE_START_ROW + i, CLIENT_COL] = receipt["client"]
     sheet[EXPENSE_START_ROW + i, CATEGORY_COL] = receipt["category"]
     amount_in_dollars = receipt["amount_in_cents"] ? receipt["amount_in_cents"].to_f/100 : receipt["amountInCents"].to_f/100
     sheet[EXPENSE_START_ROW + i, TOTAL_COL] = amount_in_dollars
   end
   file = Tempfile.new('spreadsheet')
   book.write(file.path)
   file
end

def get_col
  if ENV['MONGOHQ_URL'] 
    uri = URI.parse(ENV['MONGOHQ_URL'])
    conn = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
    db = conn.db(uri.path.gsub(/^\//, ''))
    db["expenses"]
  else
    connection = Mongo::Connection.new
    db = connection.db("mydb")
    db["expenses"]
  end
end

def generate_jruby_excel(id)
  expense = get_col.find("_id" => BSON::ObjectId(id)).to_a[0]
  
  writeable_workbook = nil
  begin
    template = java.io.File.new("template.xls")
    temp_file =	java.io.File.createTempFile(java.lang.String.valueOf(java.lang.System.currentTimeMillis()), ".xls")
    temp_file.deleteOnExit()
    workbook = Java::jxl.Workbook.getWorkbook(template)
    writeable_workbook =  Java::jxl.Workbook.createWorkbook(temp_file, workbook)
    sheet = writeable_workbook.getSheet(0)
    name_label = Java::jxl.write.Label.new(NAME_COL, NAME_ROW, "John Smith")
	  sheet.addCell(name_label)
	
    expense["receipts"].each_with_index do |receipt, i|
      date_label = Java::jxl.write.Label.new(DATE_COL, EXPENSE_START_ROW + i, receipt["date"])
      description_label = Java::jxl.write.Label.new(DESCRIPTION_COL, EXPENSE_START_ROW + i, receipt["description"])
      category_label = Java::jxl.write.Label.new(CATEGORY_COL, EXPENSE_START_ROW + i, receipt["category"])
      client_label = Java::jxl.write.Label.new(CLIENT_COL, EXPENSE_START_ROW + i, receipt["client"])
    
      amount_in_dollars = receipt["amount_in_cents"] ? receipt["amount_in_cents"].to_f/100 : receipt["amountInCents"].to_f/100
      amount_number = Java::jxl.write.Number.new(TOTAL_COL, EXPENSE_START_ROW + i, amount_in_dollars)
      
      sheet.addCell(date_label)
      sheet.addCell(description_label)
      sheet.addCell(category_label)
      sheet.addCell(client_label)
      sheet.addCell(amount_number)
    end
    
    if (expense["signature"])
      image_signature = Base64.decode64(expense["signature"])

      signature = Tempfile.new(['signature', '.png'])
      signature.write(image_signature)
      signature.rewind
      writable_image = Java::jxl.write.WritableImage.new(SIGNATURE_COL, SIGNATURE_ROW, 1, 1, java.io.File.new(signature.path))
      sheet.addImage(writable_image)
    end
 
  ensure
    if (writeable_workbook)
      writeable_workbook.write
      writeable_workbook.close
    end
  end
  temp_file.path
end
