# Product Sales aggregated on a monthly basis 
# Below example is for Croma India, FY = 2021

Select  
	s.date, s.product_code, 
    p.product, p.variant, s.sold_quantity,
    g.gross_price,
    round(g.gross_price*s.sold_quantity,2) as gross_price_total
from
fact_sales_monthly s
join dim_product p 
on s.product_code = p.product_code
join fact_gross_price g
on 
	g.product_code = s.product_code and
	g.fiscal_year = get_fiscal_year(s.date)
where 
	customer_code = 90002002 and
	get_fiscal_year(s.date)=2021
order by date Asc;


#Gross Monthly Total sales report 
#Below example for customer - Croma,India

select
   s.date,
   sum(round(sold_quantity*g.gross_price,2)) as gross_price_total
from fact_sales_monthly s
join fact_gross_price g
on 
    g.fiscal_year=get_fiscal_year(s.date) and
	g.product_code=s.product_code
where
	customer_code=90002002
group by s.date
order by date asc;


#Generate a yearly report for Croma India where there are two columns
#1. Fiscal Year
#2. Total Gross Sales amount In that year from Croma

	select
            get_fiscal_year(s.date) as fiscal_year,
            sum(round(sold_quantity*g.gross_price,2)) as yearly_sales
	from fact_sales_monthly s
	join fact_gross_price g
	on 
	    g.fiscal_year=get_fiscal_year(s.date) and
	    g.product_code=s.product_code
	where
	    customer_code=90002002
	group by get_fiscal_year(date)
	order by fiscal_year;
    
    
    # Creating stored procedure for finding monthly goss sales report 
    
    CREATE DEFINER=`root`@`localhost` PROCEDURE `get_monthly_gross_sales_for_customer`(
IN in_customer_code int)
BEGIN
	select
		s.date,
		sum(round(s.sold_quantity*g.gross_price,2)) as Monthly_sales
	from fact_sales_monthly s
	join fact_gross_price g
	on 
		g.fiscal_year=get_fiscal_year(s.date) and
		g.product_code=s.product_code
	where
		customer_code=in_customer_code
	group by s.date
	order by date asc;
END
;

    
    
#Stored Procedure to find the market badge ie. product sales above 5Million is GOLD

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_market_badge`(
IN in_market varchar(20),
IN in_fiscal_year int,
OUT out_badge varchar(20)
)
BEGIN
declare total_units_sold int default 0;

# set market to india by default
if in_market = "" then
	set in_market = "India";
end if;

#Calculate the total quantity sold
select
	sum(sold_quantity) into total_units_sold
from fact_sales_monthly s
join dim_customer c
on 
	s.customer_code = c.customer_code
where
	get_fiscal_year(s.date) = in_fiscal_year and
    c.market = in_market
group by market;

#Determine the badge is Silver or Gold

if total_units_sold > 5000000 then
	set out_badge = "Gold";
else
	set out_badge = "Silver";
end if;

END;

# After EXPLAIN ANALYZE of the query found get_fiscal_year() takes lots of time.
# One solution is to make a dim_date table so fiscal year can be easily mapped 
# duration of query decreased by almost half

SELECT  
	s.date, s.product_code, 
    p.product, p.variant, s.sold_quantity,
    g.gross_price,
    round(g.gross_price*s.sold_quantity,2) as gross_price_total,
    pre.pre_invoice_discount_pct
from
fact_sales_monthly s
join dim_product p 
on s.product_code = p.product_code
join dim_date dt
on
	dt.calendar_date = s.date
join fact_gross_price g
on 
	g.product_code = s.product_code and
	g.fiscal_year = dt.fiscal_year
join fact_pre_invoice_deductions pre
on 
	s.customer_code = pre.customer_code and
    pre.fiscal_year = dt.fiscal_year
where 
	dt.fiscal_year =2021
order by date 
limit 1000000;

#Another solution is adding fiscal year in fact_sales by generating new column
SELECT  
	s.date, s.product_code, 
    p.product, p.variant, s.sold_quantity,
    g.gross_price,
    round(g.gross_price*s.sold_quantity,2) as gross_price_total,
    pre.pre_invoice_discount_pct
from
fact_sales_monthly s
join dim_product p 
on s.product_code = p.product_code
join fact_gross_price g
on 
	g.product_code = s.product_code and
	g.fiscal_year = s.fiscal_year
join fact_pre_invoice_deductions pre
on 
	s.customer_code = pre.customer_code and
    pre.fiscal_year = s.fiscal_year
where 
	s.fiscal_year =2021
order by date 
limit 1000000;

#incorporating pre_invoice_discount
with cte1 as (SELECT  
	s.date, s.customer_code, s.product_code, 
    c.market,
    p.product, p.variant, s.sold_quantity,
    g.gross_price,
    round(g.gross_price*s.sold_quantity,2) as gross_price_total,
    pre.pre_invoice_discount_pct
from
fact_sales_monthly s
join dim_customer c
on
	s.customer_code = c.customer_code
join dim_product p 
on 	
	s.product_code = p.product_code
join fact_gross_price g
on 
	g.product_code = s.product_code and
	g.fiscal_year = s.fiscal_year
join fact_pre_invoice_deductions pre
on 
	s.customer_code = pre.customer_code and
    pre.fiscal_year = s.fiscal_year
where 
	s.fiscal_year =2021
order by date 
limit 1000000)
select *,
(gross_price_total - gross_price_total*pre_invoice_discount_pct) as 
net_invoice_sales
from cte1;

#we have many calculations coming up so to simplify things 
#we are converting this cte as view

select *,
(gross_price_total - gross_price_total*pre_invoice_discount_pct) as 
net_invoice_sales
from sales_preinv_discount; #view

#created views for sales_preinv_discounts, sales_postinv_discounts and net sales

SELECT * FROM gdb0041.net_sales;


#market share

with cte1 as (select
	c.customer,
	round(sum(net_sales)/1000000,2) as Net_sales_Millions
from
	net_sales n
	join dim_customer c
		on n.customer_code = c.customer_code
	where fiscal_year = 2021 
	group by c.customer
)
select 
	*,
	Net_sales_Millions*100/sum(Net_sales_Millions) 
    over() as Market_share
from cte1
order by Net_sales_Millions desc;

#market share of customers per region
with cte1 as (select
	c.customer, c.region,
	round(sum(net_sales)/1000000,2) as Net_sales_Millions
from
	net_sales n
	join dim_customer c
		on n.customer_code = c.customer_code
	where fiscal_year = 2021 
	group by c.customer,c.region
)
select 
	*,
	Net_sales_Millions*100/sum(Net_sales_Millions) 
    over(partition by region) as Market_share_per_region
from cte1
order by region, Net_sales_Millions desc;

#top 3 products in each division - using dense_rank
with cte1 as (select
	p.division,
    p.product,
    sum(sold_quantity)as total_quantity
from fact_sales_monthly s
join dim_product p
on s.product_code=p.product_code
where fiscal_year = 2021
group by product
),
cte2 as(select 
*,
dense_rank() over(partition by division order by total_quantity desc)
as drank
from cte1)
select *
from cte2
where drank<4;

#top 2 markets in each region on gross_sales 
with cte1 as(select
		c.market, c.region,
		round(sum(gross_price_total)/1000000,2) as gross_sales_millions
	from gross_sales g
    join dim_customer c
    on
		c.customer_code = g.customer_code
	where fiscal_year =2021
	group by market),
    
    cte2 as(
    select *,
    dense_rank() over(partition by region order by gross_sales_millions desc) as drank
    from 
    cte1)
select * from cte2
where drank <3;