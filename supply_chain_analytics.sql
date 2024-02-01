# Creating helper table - combining forecast and actual sold quantity
CREATE TABLE fact_actuals_est AS
(
	select 
		s.date as date,
	    s.fiscal_year as fiscal_year,
	    s.product_code as product_code,
	    s.customer_code as customer_code,
	    s.sold_quantity as sold_quantity,
	f.forecast_quantity as forecast_quantity
	from 
	fact_sales_monthly s
	left join fact_forecast_monthly f 
	using (date, customer_code, product_code)
	UNION
	select 
		 f.date as date,
		 f.fiscal_year as fiscal_year,
		 f.product_code as product_code,
		 f.customer_code as customer_code,
		 s.sold_quantity as sold_quantity,
		 f.forecast_quantity as forecast_quantity
	from 
	fact_forecast_monthly  f
	left join fact_sales_monthly s 
	using (date, customer_code, product_code)
);

SET SQL_SAFE_UPDATES=0;
Update fact_actuals_est
set forecast_quantity = 0
where forecast_quantity is null;

Update fact_actuals_est
set sold_quantity = 0
where sold_quantity is null;

select * from fact_actuals_est;

# Forecast Accuracy Calculations and Report

SET SQL_MODE="";
WITH forecast_err_table AS
(
	SELECT 
		s.customer_code,
        SUM(sold_quantity) AS total_sold_quantity,
        SUM(forecast_quantity) AS total_forecast_quantity,
		SUM((forecast_quantity - sold_quantity)) AS net_err,
		SUM((forecast_quantity - sold_quantity))*100/SUM(forecast_quantity) AS net_err_pct,    
		SUM(ABS(forecast_quantity - sold_quantity)) AS abs_err,
		SUM(ABS(forecast_quantity - sold_quantity))*100/SUM(forecast_quantity) AS abs_err_pct
	FROM 
	fact_actuals_est s
	WHERE s.fiscal_year = 2021
	GROUP BY customer_code
)

SELECT 
	e.*,
    c.customer,
    c.market,
    IF(abs_err_pct > 100, 0, 100-abs_err_pct) AS forecast_accuracy
FROM forecast_err_table e
JOIN dim_customer c
ON e.customer_code = c.customer_code
ORDER BY forecast_accuracy DESC
;

#Ad-hoc request: The supply chain business manager wants to see which customers’
#forecast accuracy has dropped from 2020 to 2021. Provide a complete report with
#these columns: customer_code, customer_name, market, forecast_accuracy_2020,
#forecast_accuracy_2021

#Forecast Accuracy 2021 Vs Forecast Accuracy 2020
SET SQL_MODE="";
DROP TABLE IF EXISTS forecast_accuracy_2021;
CREATE TEMPORARY TABLE forecast_accuracy_2021
WITH forecast_err_table AS
(
	SELECT 
		s.customer_code,
        c.customer,
        c.market,
        SUM(sold_quantity) AS total_sold_quantity,
        SUM(forecast_quantity) AS total_forecast_quantity,
		SUM((forecast_quantity - sold_quantity)) AS net_err,
		ROUND(SUM((forecast_quantity - sold_quantity))*100/SUM(forecast_quantity),2) AS net_err_pct,    
		SUM(ABS(forecast_quantity - sold_quantity)) AS abs_err,
		ROUND(SUM(ABS(forecast_quantity - sold_quantity))*100/SUM(forecast_quantity),2) AS abs_err_pct
	FROM 
	fact_actuals_est s
    JOIN dim_customer c
	ON s.customer_code = c.customer_code
	WHERE s.fiscal_year = 2021
	GROUP BY customer_code
)
SELECT *, 
	IF(abs_err_pct > 100, 0,100-abs_err_pct) AS forecast_accuracy 
FROM forecast_err_table 
ORDER BY forecast_accuracy DESC;
DROP TABLE IF EXISTS forecast_accuracy_2020;
CREATE TEMPORARY TABLE forecast_accuracy_2020
WITH forecast_err_table AS
(
	SELECT 
		s.customer_code,
		c.customer,
        c.market,
        SUM(sold_quantity) AS total_sold_quantity,
        SUM(forecast_quantity) AS total_forecast_quantity,
		SUM((forecast_quantity - sold_quantity)) AS net_err,
		ROUND(SUM((forecast_quantity - sold_quantity))*100/SUM(forecast_quantity),2) AS net_err_pct,    
		SUM(ABS(forecast_quantity - sold_quantity)) AS abs_err,
		ROUND(SUM(ABS(forecast_quantity - sold_quantity))*100/SUM(forecast_quantity),2) AS abs_err_pct
	FROM 
	fact_actuals_est s
	JOIN dim_customer c
	ON s.customer_code = c.customer_code
	WHERE s.fiscal_year = 2020
	GROUP BY customer_code
)
SELECT *, 
	IF(abs_err_pct > 100, 0,100-abs_err_pct) AS forecast_accuracy 
FROM forecast_err_table 
ORDER BY forecast_accuracy DESC;

SELECT 
	f_2020.customer_code,
    f_2020.customer,
    f_2020.market,
    f_2020.forecast_accuracy AS forecast_accuracy_2020,
    f_2021.forecast_accuracy AS forecast_accuracy_2021
FROM forecast_accuracy_2020 f_2020
JOIN forecast_accuracy_2021 f_2021
ON f_2020.customer_code = f_2021.customer_code
WHERE f_2021.forecast_accuracy < f_2020.forecast_accuracy
ORDER BY f_2020.forecast_accuracy DESC 
;

#49 customers have diminished forecast accuracy in 2021