/* 2. Digital Analysis
 Using the available datasets - answer the following questions using a single query for each one:*/

/* How many users are there?*/ 
select count(distinct user_id) as total_users
from users;

/* How many cookies does each user have on average?*/
with cte as (
	select user_id, count(cookie_id) as total_cookies
	from users
	group by 1)
select round(avg(total_cookies),0) as average_cookies_each_user
from cte;

/* What is the unique number of visits by all users per month?*/
with cte as (
	select distinct e.visit_id, u.user_id, month(e.event_time) as months
	from events e
	inner join users u using(cookie_id))
select months, count(*) as unique_visitors
from cte
group by 1 order by 1;

/* What is the number of events for each event type?*/
with cte as (
	select distinct e.visit_id, e.event_type, ei.event_name, date(e.event_time) as date
	from events e
	left join event_identifier ei using(event_type))
select event_type, event_name, count(*) as num_of_events
from cte
group by 1,2;

/* What is the percentage of visits which have a purchase event?*/
with cte as (
	select distinct e.visit_id, e.event_type, ei.event_name, date(e.event_time) as date
	from events e
	left join event_identifier ei using(event_type)),
cte1 as (
	select event_type, event_name, count(*) as num_of_events
	from cte
	group by 1,2)
select event_name, round((num_of_events*100/(select sum(num_of_events) from cte1)),1) as prcnt_visit
from cte1
where event_type = 3;

/* What is the percentage of visits which view the checkout page but do not have a purchase event?*/
with cte as (
	select count(distinct visit_id) as total_visit,
		(select count(distinct visit_id)
		from events e
		left join page_hierarchy p using(page_id)
		left join event_identifier e1 using(event_type)
		where p.page_name = "Checkout" and e1.event_name <> "Purchase") as visit_checkout_not_purchase
	from events)
select round((visit_checkout_not_purchase*100/total_visit),1) as percentage
from cte;

/* What are the top 3 pages by number of views?*/
select p.page_id, p.page_name, count(e.visit_id) as num_of_views
from page_hierarchy p
left join events e using(page_id)
group by 1,2
order by 3 desc limit 3;

/* What is the number of views and cart adds for each product category?*/
select p.product_category,
	sum(case when e1.event_type = 1 then 1 else 0 end) as num_of_views,
    sum(case when e1.event_type = 2 then 1 else 0 end) as num_of_cartadds
from events e
left join event_identifier e1 using(event_type)
left join page_hierarchy p using(page_id)
where p.product_category is not null
group by 1;


/* 3. Product Funnel Analysis
 Using a single SQL query - create a new output table which has the following details:

How many times was each product viewed?
How many times was each product added to cart?
How many times was each product added to a cart but not purchased (abandoned)?
How many times was each product purchased?*/
create table product_detail as (
	with cte1 as(
		 select e.visit_id,page_name, 
		 sum(case when event_name='Page View' then 1 else 0 end) as view_cnt,
		 sum(case when event_name='Add to Cart' then 1 else 0 end) as cart_adds
		 from events e 
		 left join  page_hierarchy p using(page_id) 
		 left join event_identifier e1 using(event_type)
		 where product_id is not null
		 group by 1,2),
	 cte2 as(
		 select distinct(visit_id) as purchase_id
		 from events e 
		 inner join event_identifier e1 using(event_type) 
		 where event_name = 'Purchase'),
	 cte3 as(
		 select *, 
		 (case when purchase_id is not null then 1 else 0 end) as purchase
		 from cte1 
		 left join cte2 on visit_id = purchase_id),
	 cte4 as(
		 select page_name, sum(view_cnt) as page_views, sum(cart_adds) as cart_adds, 
		 sum(case when cart_adds = 1 and purchase = 0 then 1 else 0 end) as not_purchase,
		 sum(case when cart_adds= 1 and purchase = 1 then 1 else 0 end) as purchase
		 from cte3
		 group by 1)
	select page_name, page_views, cart_adds, not_purchase, purchase
	from cte4);

/*Additionally, create another table which further aggregates the data 
for the above points but this time for each product category instead of individual products.*/
create table pcategory_details as (
	select p2.product_category, sum(p1.page_views) as page_views, 
		sum(p1.cart_adds) as cart_adds, sum(p1.not_purchase) as not_purchase, 
		sum(p1.purchase) as purchase
	from product_detail p1
	inner join page_hierarchy p2 using(page_name)
	group by 1);

/* Use your 2 new output tables - answer the following questions:

Which product had the most views, cart adds and purchases?*/
-- Most Views
select page_name as most_view_product
from product_detail
where page_views = (select max(page_views) from product_detail);

-- Most Cart Adds
select page_name as most_cartadds
from product_detail
where cart_adds = (select max(cart_adds) from product_detail);

-- Most Purchase
select page_name as most_purchase
from product_detail
where purchase = (select max(purchase) from product_detail);

/*Which product was most likely to be abandoned?*/
select page_name as most_abandoned
from product_detail
where not_purchase = (select max(not_purchase) from product_detail);

/*Which product had the highest view to purchase percentage?*/
select page_name as product, round((purchase*100/page_views),2) as percentage
from product_detail
order by 2 desc limit 1;

/*What is the average conversion rate from view to cart add?*/
select round(avg(cart_adds*100/page_views),2) as percentage
from product_detail;

/*What is the average conversion rate from cart add to purchase?*/
select round(avg(purchase*100/cart_adds),2) as percentage
from product_detail;

/* 3. Campaigns Analysis
Generate a table that has 1 single row for every unique visit_id record and has the following columns:

user_id
visit_id
visit_start_time: the earliest event_time for each visit
page_views: count of page views for each visit
cart_adds: count of product cart add events for each visit
purchase: 1/0 flag if a purchase event exists for each visit
campaign_name: map the visit to a campaign if the visit_start_time falls between 
the start_date and end_date
impression: count of ad impressions for each visit
click: count of ad clicks for each visit
(Optional column) cart_products: a comma separated text value with products added
to the cart sorted by the order they were added to the cart (hint: use the sequence_number).*/

create table campaign_analysis as (
	select u.user_id, e.visit_id, 
	  min(e.event_time) as visit_start_time,
	  sum(case when e.event_type = 1 then 1 else 0 end) as page_views,
	  sum(case when e.event_type = 2 then 1 else 0 end) as cart_adds,
	  sum(case when e.event_type = 3 then 1 else 0 end) as purchase,
	  c.campaign_name,
	  sum(case when e.event_type = 4 then 1 else 0 end) as impression, 
	  sum(case when e.event_type = 5 then 1 else 0 end) as click, 
	  ifnull(group_concat((case when p.product_id is not null and e.event_type = 2 then p.page_name else null end) 
	  order by e.sequence_number separator ', '), 'N/A') as cart_products
	from users as u
	inner join events as e using(cookie_id)
	left join campaign_identifier as c on e.event_time between c.start_date and c.end_date
	left join page_hierarchy as p using(page_id)
	group by 1, 2, 7);