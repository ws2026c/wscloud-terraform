-- =============================================================================
-- Managed Flink Studio Notebook (wsc2026-analytics-flink) 에서 실행할 SQL
--   1) 노트북을 RUN(START) -> Zeppelin 노트북 열기
--   2) 아래 셀을 순서대로 실행
--   3) 확인이 끝나면 노트북을 STOP 하여 ApplicationStatus 를 READY 로 되돌릴 것
--      (채점 2-4 는 READY 를 확인함)
-- =============================================================================

-- [셀 1] 소스 테이블 생성 -----------------------------------------------------
%flink.ssql
DROP TABLE IF EXISTS order_stream;

CREATE TABLE order_stream (
    order_id      STRING,
    product_name  STRING,
    price         BIGINT,
    quantity      INT,
    event_time    TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector'                      = 'kinesis',
    'stream'                         = 'wsc2026-order-stream',
    'aws.region'                     = 'ap-northeast-2',
    'scan.stream.initpos'            = 'TRIM_HORIZON',
    'format'                         = 'json',
    'json.timestamp-format.standard' = 'SQL'
);


-- [셀 2] 최근 1분간 총 주문 수 ------------------------------------------------
%flink.ssql(type=update)
SELECT COUNT(*) as order_count
FROM order_stream
WHERE event_time > CURRENT_TIMESTAMP - INTERVAL '1' MINUTE;


-- [셀 3] 상품별 누적 매출 -----------------------------------------------------
%flink.ssql(type=update)
SELECT product_name, SUM(price * quantity) as total_revenue
FROM order_stream
GROUP BY product_name;
