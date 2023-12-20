import boto3
import json

dynamodb = boto3.client('dynamodb')

def lambda_handler(event, context):
    try:
        keyword = event["keyword"]
        subreddit = event["subreddit"]
        
        # determine if entry exists in database
        response = dynamodb.scan(
            TableName = 'dev_subscribed_topics',
            FilterExpression = 'id = :keyword',
            ExpressionAttributeValues = {
                ':keyword': {'S': keyword}
            }
        )

        # we do not have the keyword at all
        if len(response['Items']) == 0:
            dynamodb.put_item(
                TableName='dev_subscribed_topics',
                Item={
                    "id":{
                        "S": keyword
                    },
                    "subreddit":{
                        "SS":[subreddit]
                    }
                }
            )
            return {
                'statusCode': 200,
                'body' : json.dumps('Added New Entry to Database'),
                'headers':{
                    'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                    'Access-Control-Allow-Origin' : '*',
                    'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
                }
            }
        
        # if we have, then determine if subreddit is subscribed to already
        for subscribed_subreddit in response['Items'][0]['subreddit']['SS']:
            if subscribed_subreddit == subreddit:
                return {
                    'statusCode': 200,
                    'body' : json.dumps('Subreddit is already subscribed to'),
                    'headers':{
                        'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                        'Access-Control-Allow-Origin' : '*',
                        'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
                    }
                }
                
        # if not present, then we update the list
        dynamodb.update_item(
            TableName='dev_subscribed_topics',
            Key= {
                "id": { 
                    "S": keyword
                }
            },
            UpdateExpression = 'ADD #attr1 :val1',
            ExpressionAttributeNames = {'#attr1': 'subreddit'},
            ExpressionAttributeValues = {':val1': {'SS': [subreddit]}}
        )
        return {
            'statusCode': 200,
            'body' : json.dumps('Subreddit has been added to the subscribed list'),
            'headers':{
                'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                'Access-Control-Allow-Origin' : '*',
                'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
            }
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'body' : str(e),
            'headers':{
                'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                'Access-Control-Allow-Origin' : '*',
                'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
            }
        }
