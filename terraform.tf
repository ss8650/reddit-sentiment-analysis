#################################################### IAC PROVIDER - AWS ############################################################################
# Specify AWS as our IAC provider
provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_token
}

# Create a security group for the EC2 to specify rules for inbound/outbound traffic
resource "aws_security_group" "react_group" {
  name_prefix = "react_group-"
  
  # Allows inbound HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allows inbound SSH traffic
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allows outbound HTTP traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#################################################### EC2 ############################################################################################
# Spin up the EC2 instance which hosts our frontend
resource "aws_instance" "react_ec2" {
  instance_type = "t2.micro"
  ami           = "ami-006dcf34c09e50022"
  key_name      = var.ec2_key_name
  vpc_security_group_ids = [aws_security_group.react_group.id]
  tags = {
    Name = "React EC2"
  }

  depends_on = [aws_api_gateway_deployment.deployment]

  # SSH into the instance and spin up our react app
  provisioner "remote-exec" {
    inline = [
      # Installing dependencies
      "sudo yum update -y",
      "sudo amazon-linux-extras install -y nginx1",
      "sudo yum install -y git",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash",
      ". ~/.nvm/nvm.sh",
      "nvm install 16",
      # Cloning and building the app
      "git clone https://github.com/RIT-SWEN-514-00/cloud-project-2225-swen-514-614-3c-silverlining-REACT.git",
      "cd cloud-project-2225-swen-514-614-3c-silverlining-REACT/sentiment-app",
      "npm install",
      "echo REACT_APP_API_URL=${aws_api_gateway_deployment.deployment.invoke_url}${aws_api_gateway_stage.dev_stage.stage_name} > .env",
      "npm run build",
      # Creating nginx config file
      "cd /etc/nginx/conf.d/",
      "sudo sh -c 'echo -e \"server {\n  listen 80;\n  server_name ${aws_instance.react_ec2.public_ip};\n  access_log  /var/log/nginx/access.log;\n  error_log  /var/log/nginx/error_log  debug;\n\n location / {\n  root /var/www/html/build;\n index index.html;\n}\n}\" > myapp.conf'",
      # Moving project and running server
      "sudo mkdir -p /var/www/html",
      "sudo mv /home/ec2-user/cloud-project-2225-swen-514-614-3c-silverlining-REACT/sentiment-app/build /var/www/html",
      "sudo service nginx start",
    ]
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = file(var.private_key_path)
      host = aws_instance.react_ec2.public_ip
    }
  }
}

#################################################### DYNAMO DB TABLES ##################################################################################
# Spin up DynamoDB to create the DB which holds our sentiment analysis data
resource "aws_dynamodb_table" "dynamo_db_table" {
  name           = "dev_sentiment_analysis"
  hash_key       = "id"
  range_key 	 = "date"
  read_capacity  = 10
  write_capacity = 10

  attribute {
    name = "id"
    type = "S"
  }
  
  attribute{
    name = "date"
    type = "S"
  }
}

# Dynamo DB table to hold subscribed topics
resource "aws_dynamodb_table" "dynamo_db_table_subscribe" {
  name           = "dev_subscribed_topics"
  hash_key       = "id"
  read_capacity  = 10
  write_capacity = 10

  attribute {
    name = "id"
    type = "S"
  }
}

#################################################### LAMBDA LAYER ##################################################################################
# Install the dependency requirements for the python code in our Lambda functions
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name = "python_dependencies_layer"
  filename   = "lambda_dependencies.zip"
  compatible_runtimes = ["python3.9"]
}

#################################################### LAMBDA FUNCTIONS ##################################################################################
# search code
# Deliver our Python code to Lambda in the form of a zip file so that it can create our Lambda functions
data "archive_file" "analyse_sentiment_package" {
  type        = "zip"
  source_file = "${path.module}/code/analyse_sentiment_for_keyword.py"
  output_path = "output.zip"
}

# search lambda
resource "aws_lambda_function" "lambda_analyse_sentiment_for_keyword" {
  function_name    = "analyse_sentiment_for_keyword"
  filename         = "output.zip"
  source_code_hash = data.archive_file.analyse_sentiment_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "analyse_sentiment_for_keyword.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}

# async search code
data "archive_file" "async_analyse_package" {
  type        = "zip"
  source_file = "${path.module}/code/async_analyse.py"
  output_path = "async_output.zip"
}

# async search lambda
resource "aws_lambda_function" "lambda_async_analyse" {
  function_name    = "async_analyse"
  filename         = "async_output.zip"
  source_code_hash = data.archive_file.async_analyse_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "async_analyse.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}



# /pinned post code
data "archive_file" "python_lambda_insert_subscribed_package" {
  type        = "zip"
  source_file = "${path.module}/code/insert_subscribed.py"
  output_path = "insert_output.zip"
}

# / pinned post lambda
resource "aws_lambda_function" "insert_subscribed" {
  function_name    = "insert_subscribed"
  filename         = "insert_output.zip"
  source_code_hash = data.archive_file.python_lambda_insert_subscribed_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "insert_subscribed.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}

# /pinned get code
data "archive_file" "get_subscribed_package" {
  type = "zip"
  source_file = "${path.module}/code/get_subscribed.py"
  output_path = "get_subscribed_output.zip"
}

# /pinned get lambda
resource "aws_lambda_function" "get_subscribed" {
  function_name    = "get_subscribed"
  filename         = "get_subscribed_output.zip"
  source_code_hash = data.archive_file.get_subscribed_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "get_subscribed.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}

# /results get code
data "archive_file" "get_results_package" {
  type        = "zip"
  source_file = "${path.module}/code/get_results.py"
  output_path = "get_results_output.zip"
}

# /results
resource "aws_lambda_function" "lambda_get_results" {
  function_name    = "get_results"
  filename         = "get_results_output.zip"
  source_code_hash = data.archive_file.get_results_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "get_results.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}

# /search cloudwatch invocation code
data "archive_file" "python_lambda_invoke_search_package" {
  type        = "zip"
  source_file = "${path.module}/code/invoke_search.py"
  output_path = "invoke_search_output.zip"
}

# /search cloudwatch invocation lambda
resource "aws_lambda_function" "lambda_invoke_search" {
  function_name    = "invoke_search"
  filename         = "invoke_search_output.zip"
  source_code_hash = data.archive_file.python_lambda_invoke_search_package.output_base64sha256
  role             = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
  runtime          = "python3.9"
  handler          = "invoke_search.lambda_handler"
  timeout          = 30
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
}

#################################################### CLOUD WATCH EVENT ##################################################################################
# event rule
resource "aws_cloudwatch_event_rule" "every_day"{
  name = "every-day"
  description = "fires every day"
  # schedule_expression = "cron(0/5 * * * ? *" # every 5 minutes
  schedule_expression = "cron(0 12 * * ? *)" # invoke every day
  role_arn="arn:aws:iam::${var.aws_account_id}:role/LabRole"
}

resource "aws_cloudwatch_event_target" "invoke_lambda_every_day" {
  rule = aws_cloudwatch_event_rule.every_day.name
  target_id = "lambda_invoke_search"
  arn = aws_lambda_function.lambda_invoke_search.arn
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_invoke_search" {
  statement_id = "AllowExecutionFromCloudWatch"
  action ="lambda:InvokeFunction"
  function_name=aws_lambda_function.lambda_invoke_search.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.every_day.arn
}

#################################################### API GATEWAY ####################################################################################
# Spin up the API Gateway which triggers our Lambda functions
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "sentiment_analysis_api_gateway"
}

####################################################### API GATEWAY - SEARCH ########################################################################
# Define the API Gateway Endpoint
resource "aws_api_gateway_resource" "search" {
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  path_part   = "search"
}

# Setup a get endpoint and configure the method request. Setup a query string parameter called keyword.
# The method request component defines how the incoming request to API Gateway should be processed before sending it to the backend service. 
resource "aws_api_gateway_method" "get_method_for_search" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.search.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  request_parameters = {
    "method.request.querystring.keyword" = true
    "method.request.querystring.subreddit" = false
  }
}

# Setup integration request for the get method which defines how the request from API Gateway should be transformed to be sent to the backend service. 
resource "aws_api_gateway_integration" "get_method_request_integration_for_search" {
  resource_id             = aws_api_gateway_resource.search.id
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  http_method             = aws_api_gateway_method.get_method_for_search.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.lambda_analyse_sentiment_for_keyword.invoke_arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = jsonencode({
      keyword = "$input.params('keyword')"
      subreddit = "$input.params('subreddit')"
    })
  }
  depends_on = [aws_api_gateway_method.get_method_for_search]
}

# Setup method response for the get method which defines how the response from the backend service should be processed before it is returned to the client
resource "aws_api_gateway_method_response" "get_method_response_for_search" {
  resource_id = aws_api_gateway_resource.search.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_search.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  depends_on = [aws_api_gateway_integration.get_method_request_integration_for_search]
}

# Setup integration response for the get method which defines how the response from the backend service should be transformed before it is returned to the client
resource "aws_api_gateway_integration_response" "get_method_response_integration_for_search" {
  resource_id = aws_api_gateway_resource.search.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_search.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,HEAD,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.get_method_response_for_search]
}

# Configure permissions to execute lambda function
resource "aws_lambda_permission" "permission_for_keyword_lambda_integration" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_analyse_sentiment_for_keyword.function_name
  principal     = "apigateway.amazonaws.com"

  # Documentation: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:us-east-1:${var.aws_account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/${aws_api_gateway_method.get_method_for_search.http_method}${aws_api_gateway_resource.search.path}"
}

# call module to activate cors for search
module "cors" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id = aws_api_gateway_rest_api.api_gateway.id
  api_resource_id = aws_api_gateway_resource.search.id
}

####################################################### API GATEWAY - RESULTS ########################################################################
# /results resource
resource "aws_api_gateway_resource" "results" {
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  path_part   = "results"
}

# /results get method
resource "aws_api_gateway_method" "get_method_for_results" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.results.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  request_parameters = {
    "method.request.querystring.keyword" = true
    "method.request.querystring.subreddit" = true
  }
}

# Setup integration request for the get method which defines how the request from API Gateway should be transformed to be sent to the backend service. 
resource "aws_api_gateway_integration" "get_method_request_integration_for_results" {
  resource_id             = aws_api_gateway_resource.results.id
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  http_method             = aws_api_gateway_method.get_method_for_results.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.lambda_get_results.invoke_arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = jsonencode({
      keyword = "$input.params('keyword')"
      subreddit = "$input.params('subreddit')"
    })
  }
  depends_on = [aws_api_gateway_method.get_method_for_results]
}

# Setup method response for the get method which defines how the response from the backend service should be processed before it is returned to the client
resource "aws_api_gateway_method_response" "get_method_response_for_results" {
  resource_id = aws_api_gateway_resource.results.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_results.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  depends_on = [aws_api_gateway_integration.get_method_request_integration_for_results]
}

# Setup integration response for the get method which defines how the response from the backend service should be transformed before it is returned to the client
resource "aws_api_gateway_integration_response" "get_method_response_integration_for_results" {
  resource_id = aws_api_gateway_resource.results.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_results.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,HEAD,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.get_method_response_for_results]
}

# Configure permissions to execute lambda function
resource "aws_lambda_permission" "permission_for_results_lambda_integration" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_get_results.function_name
  principal     = "apigateway.amazonaws.com"

  # Documentation: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:us-east-1:${var.aws_account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/${aws_api_gateway_method.get_method_for_results.http_method}${aws_api_gateway_resource.results.path}"
}

# call module to activate cors for search
module "cors_for_results" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id = aws_api_gateway_rest_api.api_gateway.id
  api_resource_id = aws_api_gateway_resource.results.id
}

####################################################### API GATEWAY - PINNED ########################################################################
# establish pinned resource
resource "aws_api_gateway_resource" "pinned"{
  parent_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  path_part = "pinned"
}

# /pinned post request
resource "aws_api_gateway_method" "post_method_for_pinned"{
  authorization = "NONE"
  http_method = "POST"
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  request_parameters = {
    "method.request.querystring.keyword" = true
    "method.request.querystring.subreddit" = true
  }
}

# /pinned request integration
resource "aws_api_gateway_integration" "post_method_request_integration_for_pinned"{
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.post_method_for_pinned.http_method
  integration_http_method = "POST"
  type = "AWS"
  uri = aws_lambda_function.insert_subscribed.invoke_arn
  passthrough_behavior = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = jsonencode({
      keyword = "$input.params('keyword')",
      subreddit = "$input.params('subreddit')"
    })
  }
  depends_on = [aws_api_gateway_method.post_method_for_pinned]
}

# /pinned response
resource "aws_api_gateway_method_response" "post_method_response_for_pinned"{
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.post_method_for_pinned.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  depends_on = [aws_api_gateway_integration.post_method_request_integration_for_pinned]
} 

# /pinned response integration
resource "aws_api_gateway_integration_response" "post_method_response_integration_for_pinned" {
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.post_method_for_pinned.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,HEAD,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.post_method_response_for_pinned]
}

# provide permissions for /pinned post lambda invoke
resource "aws_lambda_permission" "permission_for_insert_pinned" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.insert_subscribed.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:us-east-1:${var.aws_account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/${aws_api_gateway_method.post_method_for_pinned.http_method}${aws_api_gateway_resource.pinned.path}"
  # Documentation: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
}

# /pinned get request
resource "aws_api_gateway_method" "get_method_for_pinned"{
  authorization = "NONE"
  http_method = "GET"
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

# /pinned get request integration
resource "aws_api_gateway_integration" "get_method_request_integration_for_pinned"{
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_pinned.http_method
  integration_http_method = "POST"
  type = "AWS"
  uri = aws_lambda_function.get_subscribed.invoke_arn
  passthrough_behavior = "WHEN_NO_TEMPLATES" 
  depends_on = [aws_api_gateway_method.get_method_for_pinned]
}

# /pinned get response
resource "aws_api_gateway_method_response" "get_method_response_for_pinned"{
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_pinned.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  depends_on = [aws_api_gateway_integration.get_method_request_integration_for_pinned]
}

# /pinned get response integration 
resource "aws_api_gateway_integration_response" "get_method_response_integration_for_pinned" {
  resource_id = aws_api_gateway_resource.pinned.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  http_method = aws_api_gateway_method.get_method_for_pinned.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,HEAD,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.get_method_response_for_pinned]
}

# provide permissions for /pinned get lambda invoke
resource "aws_lambda_permission" "permission_for_get_pinned" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_subscribed.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:us-east-1:${var.aws_account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/${aws_api_gateway_method.get_method_for_pinned.http_method}${aws_api_gateway_resource.pinned.path}"
  # Documentation: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
}

# call module to activate cors for pinned
module "cors_pinned" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id = aws_api_gateway_rest_api.api_gateway.id
  api_resource_id = aws_api_gateway_resource.pinned.id
}

####################################################### API GATEWAY - DEPLOYMENT ########################################################################
# Create a deployment stage called dev
resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "dev"
}

# Deploy the API gateway
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.get_method_request_integration_for_search,
    aws_api_gateway_integration.post_method_request_integration_for_pinned,
    aws_api_gateway_integration.get_method_request_integration_for_pinned,
    aws_api_gateway_integration.get_method_request_integration_for_results
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

# Print the url of the API gateway onto the terminal
output "api_gateway_root_endpoint" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}${aws_api_gateway_stage.dev_stage.stage_name}"
}

# Print the public ip of the EC2
output "ec2_ip" {
  value = "${aws_instance.react_ec2.public_ip}"
}
