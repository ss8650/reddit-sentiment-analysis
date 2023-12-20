# Reddit Sentiment Analysis
An online cloud system to perform sentiment analysis on Reddit comments when provided a keyword by the user.
- Built in Python 3.9 and React.
- Uses Terraform for IaC development and deployment.
- Uses the following AWS Services:
    - EC2 to host the React frontend.
    - API Gateway to connect the EC2 to our backend.
    - Lambda functions to operate as a serverless backend.
    - Amazon Comprehend to generate the analysis results.
    - DynamoDB to store and access the results.
    - Cloudwatch to trigger daily automatic information updates.
  
## Team 3c - Silver Lining
Brought to you by the brilliant minds of:
- Sam Singh Anantha
- Will Petersen
- Robert Yamasaki
- Alex Mandigo

## Prerequisites
- A working Terraform installation
- Have an AWS account of some sort

## Project Setup and Deployment
1. Clone this respository and cd into it.
2. Sign into your AWS Lab account and start a new session.
3. Copy a valid EC2 key pair (.pem filetype only) into the root of the repository folder.
4. Create an `env.tfvars` file, using the `env.tfvars.example` template, and fill it in using your credentials and key information. **If you're using an AWS Lab account**, you will need to start a new Lab session and copy over the access key, secret access key, and session token information **every time** the previous Lab session ends. This can be found once the lab has been started by clicking on "AWS Details" and then "Show" under "AWS CLI".
5. Open a terminal in the root of the repository and run these two Terraform commands:
```
terraform init
```
```
terraform apply -var-file=env.tfvars -auto-approve
```
6. Once Terraform has finished, leave the terminal open for now and instead navigate to your AWS Console and select your API Gateway.
7. Click on "sentiment_analysis_gateway"
8. Click on the **/pinned** resource, then the Actions dropdown, and select ENABLE CORS.
9. Next to **Gateway Responses for sentiment_analysis_api_gateway API**, check the options for **DEFAULT 4XX** and **DEFAULT 5XX**, click “Enable CORS and replace existing CORS headers”, then click “Yes, replace existing values” on the pop-up window
10. Repeat steps 8 and 9 for the other resources
11. Click the Actions dropdown and select "Deploy API"
12. In the pop-up window, select “dev” as the deployment stage and hit **Deploy**
13. Back in your terminal, copy the EC2 IP address that was provided and paste it into your browser. You are now ready to use the application!

## Project Shutdown
To end the application (and save on AWS costs), run:
```
terraform destroy -var-file=env.tfvars
```

## Known bugs and disclaimers
(It may be the case that your implementation is not perfect.)

Document any known bug or nuisance.
If any shortcomings, make clear what these are and where they are located.

## License
MIT License

See LICENSE for details.
