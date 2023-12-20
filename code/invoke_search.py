import boto3
import json

dynamodb = boto3.client('dynamodb')
client = boto3.client('lambda')

def lambda_handler(event, context):
    response = dynamodb.scan(
        TableName = 'dev_subscribed_topics'
    )

    for item in response['Items']:
        for subscribed_reddit in item['reddit']['SS']:
            obj = {'keyword': item['id']['S'], 'subreddit': subscribed_reddit}
            print(obj)
            
            client_response = client.invoke(
                FunctionName = 'analyse_sentiment_for_keyword',
                InvocationType='RequestResponse',
                Payload=json.dumps(obj)
            )
            print(client_response)
    return 




