{
  "StartAt": "CheckS3File",
  "States": {
    "CheckS3File": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:headObject",
      "Parameters": { "Bucket": "wsc2026-student-score-bucket-<비번호>", "Key.$": "$.key" },
      "ResultPath": null,
      "Catch": [{ "ErrorEquals": ["States.ALL"], "Next": "FileNotFound" }],
      "Next": "ProcessStudentData"
    },
    "ProcessStudentData": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": { "FunctionName": "<처리 Lambda ARN>", "Payload": { "key.$": "$.key" } },
      "ResultSelector": { "statusCode.$": "$.Payload.statusCode" },
      "ResultPath": "$.result",
      "Retry": [{ "ErrorEquals": ["States.TaskFailed"], "IntervalSeconds": 2, "MaxAttempts": 3, "BackoffRate": 2 }],
      "Catch": [{ "ErrorEquals": ["States.ALL"], "ResultPath": "$.error", "Next": "MoveToError" }],
      "Next": "CheckResult"
    },
    "CheckResult": {
      "Type": "Choice",
      "Choices": [{ "Variable": "$.result.statusCode", "NumericEquals": 200, "Next": "MoveToProcessed" }],
      "Default": "MoveToError"
    },
    "MoveToProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "wsc2026-student-score-bucket-<비번호>",
        "CopySource.$": "States.Format('wsc2026-student-score-bucket-<비번호>/{}', $.key)",
        "Key": "processed/test.csv"
      },
      "ResultPath": null, "Next": "DeleteAfterProcessed"
    },
    "DeleteAfterProcessed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": { "Bucket": "wsc2026-student-score-bucket-<비번호>", "Key.$": "$.key" },
      "ResultPath": null, "End": true
    },
    "MoveToError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:copyObject",
      "Parameters": {
        "Bucket": "wsc2026-student-score-bucket-<비번호>",
        "CopySource.$": "States.Format('wsc2026-student-score-bucket-<비번호>/{}', $.key)",
        "Key": "error/test.csv"
      },
      "ResultPath": null, "Next": "DeleteAfterError"
    },
    "DeleteAfterError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:s3:deleteObject",
      "Parameters": { "Bucket": "wsc2026-student-score-bucket-<비번호>", "Key.$": "$.key" },
      "ResultPath": null, "Next": "Failed"
    },
    "Failed": { "Type": "Fail" },
    "FileNotFound": { "Type": "Fail" }
  }
}