import boto3
import requests
from datetime import datetime
from datetime import timedelta
from better_profanity import profanity
import json

def fetch_comments_from_reddit(keyword, subreddit, after):
    # PUSH SHIFT 
    before = str(after - 1) + 'd'
    after = str(after) + 'd'
    api_url = "https://api.pushshift.io/reddit/search/comment"
    search_params = {"q": keyword, "size": 25, "fields": "body", "after": after, "before": before}
    print('search')
    print(search_params)
    if subreddit != "all":
        search_params["subreddit"] = subreddit
    response = requests.get(api_url, params=search_params).json()
    print('response')
    print(response)
    data = response["data"]
    # only extra ct 620 characters because of comprehend's processing limitations
    return [comment["body"][:620] for comment in data]

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

def create_response_object(keyword, subreddit, comment_examples, approval_rating, sentiments_breakdown, date):
    comment_examples["positive"] = profanity.censor(comment_examples["positive"])
    comment_examples["negative"] = profanity.censor(comment_examples["negative"])
    comment_examples["neutral"] = profanity.censor(comment_examples["neutral"])
    comment_examples["mixed"] = profanity.censor(comment_examples["mixed"])
    response = {"keyword": keyword,
                "subreddit": subreddit,
                "comments": comment_examples,
                "approval_rating": approval_rating,
                "sentiments_breakdown": sentiments_breakdown}
                
    timestamp = (datetime.utcnow() - timedelta(days=date)).strftime("%Y%m%d")

    response["id"] = str(keyword) + "_" + str(subreddit) + "_" + str(timestamp)
    response["timestamp"] = timestamp
    print(response)
    return response

def save_in_dynamo_db(item):
    print("test")
    print(item)
    dynamodb = boto3.client('dynamodb')
    response = dynamodb.put_item(
        TableName='dev_sentiment_analysis',
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
                        {
                            "N": str(item["sentiments_breakdown"]["positive"])
                        },
                    "negative":
                        {
                            "N": str(item["sentiments_breakdown"]["negative"])
                        },
                    "neutral":
                        {
                            "N": str(item["sentiments_breakdown"]["neutral"])
                        },
                    "mixed":
                        {
                            "N": str(item["sentiments_breakdown"]["mixed"])
                        }
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
        }
    )
    print(response)



# give it a date, search
def lambda_handler(event, context):
    try:
        keyword = event["keyword"]
        after_date = event["date"]  # 1- > 7

        if event["subreddit"] == "":
            subreddit = "all"
        else:
            subreddit = event["subreddit"]
            
            
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
        
        print("fetch_comments_from_reddit")
        comments = fetch_comments_from_reddit(keyword, subreddit, after_date)

        print("batch")
        # analyzing sentiments in a batch
        batches = [comments[i:i+25] for i in range(0, len(comments), 25)]
        for batch in batches:
            batch_sentiments = analyze_sentiments(batch)
            for sentiment_data in batch_sentiments:
                sentiment = sentiment_data["Sentiment"].lower()
                sentiments_count[sentiment] += 1
                if get_sentiment_confidence(sentiment, sentiment_data) > sentiments_confidence[sentiment]:
                    sentiments_examples[sentiment] = sentiment_data["comment"]
                    sentiments_confidence[sentiment] = get_sentiment_confidence(
                        sentiment, sentiment_data)
        print(sentiments_count)
        approval_rating = calculate_approval_rating(sentiments_count)
        response = create_response_object(keyword,
                                          subreddit,
                                          sentiments_examples,
                                          approval_rating,
                                          sentiments_count,
                                          after_date - 1)
        save_in_dynamo_db(response)
        return {
            'statusCode': 200,
            'body' : json.dumps(comments),
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
        
