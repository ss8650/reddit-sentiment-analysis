import boto3
import requests
from datetime import datetime
from datetime import timedelta
from better_profanity import profanity
import json
import praw
from praw.models import MoreComments
from boto3.dynamodb.types import TypeDeserializer


def fetch_comments_from_reddit(keyword, subreddit):
    # # PUSH SHIFT
    # api_url = "https://api.pushshift.io/reddit/search/comment"
    # search_params = {"q": keyword, "size": 25, "fields": "body"}
    # if subreddit != "all":
    #     search_params["subreddit"] = subreddit
    # response = requests.get(api_url, params=search_params).json()
    # data = response["data"]
    # # only extra ct 620 characters because of comprehend's processing limitations
    # return [comment["body"][:620] for comment in data]
    
    reddit = praw.Reddit(client_id="5kaF2EBbCbxKuY3WqYq4ZQ",
                 client_secret="wa7a3epXWLkQwhPw1vSYV4p_ZgrnTQ",
                 user_agent="team3c_silver_lining")
    all = reddit.subreddit(subreddit)
    comment_list = []
    for post in all.search(keyword, limit=10, sort="hot"):
        # count = 0
        # for comment in post.comments:
        #     if isinstance(comment, MoreComments):
        #         continue
        #     if count == 10:
        #         break
        #     bodyText = comment.body
        #     if bodyText != '[removed]':
        #         comment_list.append(bodyText)
        #         count += 1
        #     count += 1
        comment_list.append(post.title)
    return [title[:620] for title in comment_list]


def analyze_sentiments(batch):
    comprehend = boto3.client('comprehend')
    response = comprehend.batch_detect_sentiment(
        TextList=batch, LanguageCode='en')['ResultList']
    # mapping the comments to the sentiments based on index
    sentiments_data = []
    for item in response:
        index = item['Index']
        item["comment"] = batch[index]
        sentiments_data.append(item)
    return sentiments_data


def get_sentiment_confidence(sentiment, sentiment_data):
    sentiment = sentiment.capitalize()
    sentiment_scores = sentiment_data["SentimentScore"]
    return sentiment_scores[sentiment]

# Calculates an approval rating based off of a weighted average of the sentiment results


def calculate_approval_rating(sentiments_count):
    rating = 0
    positive_rating_score = 2
    mixed_rating_score = 1
    negative_rating_score = 0

    maximum_rating = (sentiments_count["positive"] +
                      sentiments_count["negative"] +
                      sentiments_count["mixed"]) * positive_rating_score

    # If all of our counts are zero, need to avoid attempting to divide by zero
    if maximum_rating == 0:
        return 0

    rating += sentiments_count["positive"] * positive_rating_score
    rating += sentiments_count["negative"] * negative_rating_score
    rating += sentiments_count["mixed"] * mixed_rating_score
    rating = (rating * 100) / maximum_rating

    return rating


def create_response_object(keyword, subreddit, comment_examples, approval_rating, sentiments_breakdown):
    comment_examples["positive"] = profanity.censor(
        comment_examples["positive"])
    comment_examples["negative"] = profanity.censor(
        comment_examples["negative"])
    comment_examples["neutral"] = profanity.censor(comment_examples["neutral"])
    comment_examples["mixed"] = profanity.censor(comment_examples["mixed"])
    response = {"keyword": keyword,
                "subreddit": subreddit,
                "comments": comment_examples,
                "approval_rating": approval_rating,
                "sentiments_breakdown": sentiments_breakdown}
    timestamp = datetime.utcnow().strftime("%Y%m%d")
    response["id"] = str(keyword) + "_" + str(subreddit) + "_" + str(timestamp)
    response["timestamp"] = datetime.utcnow().strftime("%Y%m%d")
    return response


def save_in_dynamo_db(item):
    dynamodb = boto3.client('dynamodb')
    response = dynamodb.put_item(TableName='dev_sentiment_analysis',
                                 Item={
                                     "id": {
                                         "S": item["id"]
                                     },
                                     "keyword": {
                                         "S": item["keyword"]
                                     },
                                     "subreddit": {
                                         "S": item["subreddit"]
                                     },
                                     "date": {
                                         "S": item["timestamp"]
                                     },
                                     "approval_rating": {
                                         "N": str(item["approval_rating"])
                                     },
                                     "sentiments_breakdown": {
                                         "M": {
                                             "positive":
                                             {"N": str(
                                                 item["sentiments_breakdown"]["positive"])},
                                             "negative":
                                             {"N": str(
                                                 item["sentiments_breakdown"]["negative"])},
                                             "neutral":
                                             {"N": str(
                                                 item["sentiments_breakdown"]["neutral"])},
                                             "mixed":
                                             {"N": str(
                                                 item["sentiments_breakdown"]["mixed"])}
                                         }
                                     },
                                     "comments": {
                                         "M": {
                                             "positive": {"S": item["comments"]["positive"]},
                                             "negative": {"S": item["comments"]["negative"]},
                                             "neutral": {"S": item["comments"]["neutral"]},
                                             "mixed": {"S": item["comments"]["mixed"]}
                                         }
                                     }
                                 })

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

# Handler that gets called when a Lambda trigger occurs
def lambda_handler(event, context):
    try:
        keyword = event["keyword"]

        # # Check for specified subreddit
        if event["subreddit"] == "":
            subreddit = "all"
        else:
            subreddit = event["subreddit"]

        # determine if we already have an entry for the current day
        dynamodb = boto3.client('dynamodb')
        date = datetime.utcnow().strftime("%Y%m%d")
        pk = str(keyword) + "_" + str(subreddit) + "_" + str(date)
        response = dynamodb.query(
            TableName='dev_sentiment_analysis',
            KeyConditionExpression='id=:id',
            ExpressionAttributeValues={
                ':id': {'S': pk}
            }
        )

        # if we find an item, we have data for this day and should return it
        if len(response['Items']) > 0:
            ret = []
            for item in response['Items']:
                ret.append(dynamo_obj_to_python_obj(item))
            
            
            return {
                'statusCode': 200,
                'body': json.dumps(ret[0]),
                'headers': {
                    'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
                }
            }
        # otherwise, we query up previous week to search

        sentiments_count = {"positive": 0,
                            "negative": 0,
                            "mixed": 0,
                            "neutral": 0}
        sentiments_confidence = {"positive": 0,
                                 "negative": 0,
                                 "mixed": 0,
                                 "neutral": 0}
        sentiments_examples = {"positive": "",
                               "negative": "",
                               "mixed": "",
                               "neutral": ""}

        comments = fetch_comments_from_reddit(keyword, subreddit)

        batch_sentiments = analyze_sentiments(comments)
        for sentiment_data in batch_sentiments:
            sentiment = sentiment_data["Sentiment"].lower()
            sentiments_count[sentiment] += 1
            if get_sentiment_confidence(sentiment, sentiment_data) > sentiments_confidence[sentiment]:
                sentiments_examples[sentiment] = sentiment_data["comment"]
                sentiments_confidence[sentiment] = get_sentiment_confidence(
                    sentiment, sentiment_data)
        approval_rating = calculate_approval_rating(sentiments_count)
        response = create_response_object(keyword,
                                          subreddit,
                                          sentiments_examples,
                                          approval_rating,
                                          sentiments_count)
        save_in_dynamo_db(response)
        for i in range(1, 9):
            obj = {'keyword': keyword, 'subreddit': subreddit, 'date': i}
            client = boto3.client('lambda')
            client.invoke(
                FunctionName='async_analyse',
                InvocationType='Event',
                Payload=json.dumps(obj),
            )
        return {
            'statusCode': 200,
            'body': json.dumps(response),
            'headers': {
                'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
            }
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'body': str(e),
            'headers': {
                'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Amz-Date,X-Amz-Security-Token,X-Api-Key',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'OPTIONS, POST, GET'
            }
        }
