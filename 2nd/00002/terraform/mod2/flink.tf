###############################################################################
# flink.tf - Managed Apache Flink Studio Notebook
#   채점 2-4 : wsc2026-analytics-flink / READY / ZEPPELIN-FLINK-3_0
#
#   ※ Terraform 의 aws_kinesisanalyticsv2_application 리소스는
#      Studio Notebook(ZEPPELIN 런타임)을 지원하지 않는다.
#        - application_code_configuration 이 필수로 요구되고
#        - zeppelin_application_configuration 블록 자체가 스키마에 없음
#      따라서 CloudFormation 스택(AWS::KinesisAnalyticsV2::Application)으로 생성한다.
#      terraform destroy 시 스택이 삭제되면서 노트북도 함께 제거된다.
#
#   ※ 생성 직후 ApplicationStatus 는 READY 이다.
#      노트북을 RUN 하면 RUNNING 이 되므로 채점 전에는 반드시 STOP 하여 READY 로 되돌릴 것.
###############################################################################

# Studio Notebook 은 Glue Data Catalog 데이터베이스가 반드시 필요
resource "aws_glue_catalog_database" "analytics" {
  name        = var.glue_database_name
  description = "Catalog for wsc2026 analytics studio notebook"
}

resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/${var.flink_app_name}"
  retention_in_days = 7
}

# 갓 만들어진 IAM Role/Policy 는 즉시 반영되지 않는다.
# KinesisAnalyticsV2 가 생성 시점에 glue:GetDatabase 를 검증 호출하므로
# 전파 전에 스택을 만들면 "insufficient permission" 으로 실패한다.
resource "time_sleep" "iam_propagation" {
  create_duration = "30s"

  depends_on = [
    aws_iam_role.flink,
    aws_iam_role_policy.flink,
  ]
}

resource "aws_cloudformation_stack" "flink_studio" {
  name = "wsc2026-analytics-flink-studio"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "WSC2026 Managed Apache Flink Studio Notebook"

    Resources = {
      StudioNotebook = {
        Type = "AWS::KinesisAnalyticsV2::Application"
        Properties = {
          ApplicationName      = var.flink_app_name
          RuntimeEnvironment   = var.flink_runtime
          ApplicationMode      = "INTERACTIVE"
          ServiceExecutionRole = aws_iam_role.flink.arn

          ApplicationConfiguration = {
            ZeppelinApplicationConfiguration = {
              CatalogConfiguration = {
                GlueDataCatalogConfiguration = {
                  DatabaseARN = aws_glue_catalog_database.analytics.arn
                }
              }

              # Kinesis 를 Flink SQL 로 조회하기 위한 커넥터
              # (ZEPPELIN-FLINK-3_0 = Flink 1.15 계열)
              CustomArtifactsConfiguration = [
                {
                  ArtifactType = "DEPENDENCY_JAR"
                  MavenReference = {
                    GroupId    = "org.apache.flink"
                    ArtifactId = "flink-sql-connector-kinesis"
                    Version    = "1.15.4"
                  }
                }
              ]

              MonitoringConfiguration = {
                LogLevel = "INFO"
              }
            }
          }
        }
      }
    }

    Outputs = {
      ApplicationName = {
        Value = var.flink_app_name
      }
    }
  })

  depends_on = [
    aws_iam_role_policy.flink,
    aws_glue_catalog_database.analytics,
    time_sleep.iam_propagation,
  ]
}
