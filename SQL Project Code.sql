-- AOV CACULATION
-- Filter out completed orders by distinct order IDs
CREATE VIEW AOV AS
WITH OrderAll1 AS (SELECT * 
FROM OrderAll_QT 
WHERE Trang_Thai_Don_Hang = 'Hoàn thành' 
GROUP BY Ma_don_hang)
-- Calculate AOV per month for completed orders
SELECT extract(year_month from Ngay_dat_hang) AS 'Month_year',
round(sum(Tong_gia_tri_don_hang) / count(Ma_don_hang),0) AS 'AOV' 
FROM OrderAll1 
GROUP BY extract(year_month from Ngay_dat_hang)
-- BASKET ANALYSIS: Calculate the frequency of any set of 2 products
-- Select orders with more than 1 product
CREATE VIEW  Basket_analysis AS
WITH CountProducts AS 
(SELECT Ma_don_hang,
COUNT(SKU_san_pham) AS NumberofProducts
FROM OrderAll_QT
GROUP BY Ma_don_hang
HAVING NumberofProducts>=2),
-- Get the ID and product name of orders with more than 1 product
Info AS
(SELECT CountProducts.Ma_don_hang,
OrderAll_QT.SKU_san_pham, OrderAll_QT.Ten_san_pham
FROM CountProducts
JOIN OrderAll_QT 
ON CountProducts.Ma_don_hang = OrderAll_QT.Ma_don_hang)
-- Get the frequency of any set of 2 products
SELECT CONCAT(Info1.SKU_san_pham, Info2.SKU_san_pham) AS Combination,
Info1.Ten_san_pham AS San_pham1,
Info2.Ten_san_pham AS San_pham2,
COUNT(*) AS Frequence
FROM Info AS Info1
JOIN Info AS Info2 # Join info table itself to combine the combos of 2 products
ON Info1.Ma_don_hang = Info2.Ma_don_hang
WHERE Info1.SKU_san_pham < Info2.SKU_san_pham # Avoid duplcating the combination
GROUP BY Info1.SKU_san_pham, Info2.SKU_san_pham
ORDER BY COUNT(*) DESC # Show the highest combined frequencies
-- RFM ANALYSIS: classify customer
-- Get the completed orders
CREATE VIEW RFM_Analysis AS 
WITH RFMtable AS (SELECT Ma_don_hang, Ngay_dat_hang, 
Tong_gia_tri_don_hang, Nguoi_Mua 
FROM OrderAll_QT 
WHERE Trang_Thai_Don_Hang = 'Hoàn thành' 
GROUP BY Ma_don_hang),
-- Calculate each metrics in REM by customers 
RFMmetrics AS (SELECT Nguoi_Mua AS Customer,
to_days('2023-02-28') - to_days(max(Ngay_dat_hang)) AS Recency, # Calculate the recency
count(Ma_don_hang) AS Frequency, # Calculate the frequency
sum(Tong_gia_tri_don_hang) AS Monetary # Calculate the monetary
FROM RFMtable 
GROUP BY Nguoi_Mua), 
-- Find the percentile of the frequency and monetary metrics
RFMpercentrank AS (SELECT *,
percent_rank() OVER (ORDER BY Frequency) AS frequency_percent_rank,
percent_rank() OVER (ORDER BY Monetary) AS monetary_percent_rank 
FROM RFMmetrics), 
-- Divide the rankings for each metric
RFMrank AS (SELECT *,
CASE # classify based on the period time of dataset (90 days)
WHEN Recency BETWEEN 0 AND 60 THEN 3 
WHEN Recency BETWEEN 60 AND 80 THEN 2 
ELSE 1 
END AS recency_rank, 
CASE 
WHEN frequency_percent_rank BETWEEN 0.9 AND 1 THEN 3 # The number of customers bought 1 orders account for about 90%
WHEN frequency_percent_rank BETWEEN 0.5 AND 0.9 THEN 2 
ELSE 1 
END AS frequency_rank,
CASE
WHEN monetary_percent_rank BETWEEN 0.8 AND 1 THEN 3 # Select the 20% of customers with the highest revenue
WHEN monetary_percent_rank BETWEEN 0.5 AND 0.8 THEN 2 
ELSE 1 
END AS monetary_rank 
from RFMpercentrank), 
-- Explain each rank of each metrics and group customers
RFMrankconcat AS (select *,
CASE 
WHEN recency_rank = 1 THEN '1-Đã lâu không mua hàng' 
WHEN recency_rank = 2 THEN '2-Bình thường' 
ELSE '3-Active' 
END AS recency_segment, # explain clearly for each rank of recency
CASE 
WHEN frequency_rank = 1 THEN '1-Ít mua hàng' 
WHEN frequency_rank = 2 THEN '2-Bình thường' 
ELSE '3-Mua thường xuyên' 
END AS frequency_segment, # Explain clearly for each rank of frequency
CASE 
WHEN monetary_rank = 1 THEN '1-Chi tiêu ít' 
WHEN monetary_rank = 2 THEN '2-Bình thường' 
ELSE '3-Chi tiêu nhiều' 
END AS monetary_segment, # Explain clearly for each rank of monetary
concat(recency_rank, frequency_rank, monetary_rank) AS rfm_rank # Combine 3 features to group customers
FROM RFMrank)
-- Classify customer segments based on outstanding features
SELECT *,
CASE 
WHEN rfm_rank = '333' THEN 'KH VIP' 
WHEN rfm_rank = '111' THEN 'KH có khả năng rời bỏ' 
WHEN right(rfm_rank, 1) = '3' THEN 'KH chi nhiều' 
WHEN substr(rfm_rank, 2, 1) = '3' THEN 'KH trung thành' 
WHEN left(rfm_rank,2) = '31' THEN 'KH mới' 
ELSE 'KH bình thường' 
END AS customer_segment 
FROM RFMrankconcat
