import json
import boto3
import os
import urllib.parse
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    print("Event received:", json.dumps(event))

  
    source_bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
    
  
    dest_bucket = os.environ['DEST_BUCKET']

    try:
      
        response = s3.get_object(Bucket=source_bucket, Key=key)
        raw_data = response['Body'].read().decode('utf-8')
        
      
        processed_data = json.loads(raw_data)
        processed_data['processed_timestamp'] = datetime.now().isoformat()
        
    
        dest_key = f"processed_{key}"
        s3.put_object(
            Bucket=dest_bucket, 
            Key=dest_key, 
            Body=json.dumps(processed_data)
        )
        
        return {'statusCode': 200, 'body': f"Successfully processed {key}"}
        
    except Exception as e:
        print(f"Error: {e}")
        raise e