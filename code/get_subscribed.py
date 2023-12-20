import boto3
import json
from datetime import datetime
from boto3.dynamodb.types import TypeDeserializer


dynamodb = boto3.client('dynamodb')

def dynamo_obj_to_python_obj(dynamo_obj: dict) -> dict:
    deserializer = TypeDeserializer()
    obj = {
        k: deserializer.deserialize(v) 
        for k, v in dynamo_obj.items()
    } 
    obj['sentiments_breakdown']['neutral'] = float(obj['sentiments_breakdown']['neutral'])
    obj['sentiments_breakdown']['negative'] = float(obj['sentiments_breakdown']['negative'])
    obj['sentiments_breakdown']['mixed'] = float(obj['sentiments_breakdown']['mixed'])
    obj['sentiments_breakdown']['positive'] = float(obj['sentiments_breakdown']['positive'])
    obj['approval_rating'] = float(obj['approval_rating'])

    return obj

def lambda_handler(event, context):
    response = dynamodb.scan(
        TableName = 'dev_subscribed_topics'
    )

    ret = []
    for item in response['Items']:
        for subscribed_subreddit in item['subreddit']['SS']:
            keyword = item['id']['S']
            subreddit = subscribed_subreddit
            date = datetime.utcnow().strftime("%Y%m%d")
            print(subreddit)
            response2 = dynamodb.get_item( 
                TableName = "dev_sentiment_analysis",
                Key={
                    "id":{
                        "S" : f"{keyword}_{subreddit}_{date}"
                    },
                    "date":{
                        "S" : date
                    }
                }
            )
            ret.append(dynamo_obj_to_python_obj(response2['Item']))
    return {
        'statusCode': 200,
        'body' : json.dumps(ret),
        'headers':{
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin' : '*',
            'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
        }
    }




