import json
import os
import base64
from collections import OrderedDict
import boto3
from botocore.exceptions import ClientError

REGION = 'ap-northeast-2'
RAW_TABLE_NAME = os.environ.get('TABLE_NAME')

if not RAW_TABLE_NAME:
    raise RuntimeError("TABLE_NAME environment variable is not set.")

TABLE_NAME = RAW_TABLE_NAME
if RAW_TABLE_NAME.startswith('AQIC'):
    try:
        kms = boto3.client('kms', region_name=REGION)
        decoded_binary = base64.b64decode(RAW_TABLE_NAME)
        TABLE_NAME = kms.decrypt(CiphertextBlob=decoded_binary)['Plaintext'].decode('utf-8')
    except Exception:
        TABLE_NAME = 'wsc2026-book-table'

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    query_params = event.get('queryStringParameters') or {}
    booking_id = query_params.get('booking_id')
    
    if not booking_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'message': 'Missing required parameter: booking_id'})
        }
    
    try:
        from boto3.dynamodb.conditions import Key
        response = table.query(
            IndexName='BookingIdIndex',
            KeyConditionExpression=Key('booking_id').eq(booking_id)
        )
        
        items = response.get('Items', [])
        
        if not items:
            return {
                'statusCode': 404,
                'body': json.dumps({'message': f'Booking with id {booking_id} not found'})
            }
            
        item = items[0]
        
        ordered_body = OrderedDict([
            ("client_id", item.get("client_id")),
            ("username", item.get("username")),
            ("email", item.get("email")),
            ("concert_name", item.get("concert_name")),
            ("created_at", item.get("created_at"))
        ])
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(ordered_body)
        }
        
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Internal Server Error', 'error': e.response['Error']['Message']})
        }
