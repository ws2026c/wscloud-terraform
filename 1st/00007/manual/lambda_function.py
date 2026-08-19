import json
import os
import boto3

TABLE_NAME = os.environ.get("TABLE_NAME")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        query_params = event.get("queryStringParameters") or {}
        
        booking_id = query_params.get("booking_id")
        email = query_params.get("email")
        concert_name = query_params.get("concert_name")

        if not booking_id:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Missing required parameter: booking_id"})
            }

        response = table.get_item(Key={"booking_id": booking_id})
        item = response.get("Item")

        if not item:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found"})
            }

        if email and item.get("email") != email:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found with specified email"})
            }

        if concert_name and item.get("concert_name") != concert_name:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found with specified concert_name"})
            }

        result = {
            "booking_id": item.get("booking_id"),
            "client_id": item.get("client_id"),
            "username": item.get("username"),
            "email": item.get("email"),
            "concert_name": item.get("concert_name"),
            "created_at": item.get("created_at")
        }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result)
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }
