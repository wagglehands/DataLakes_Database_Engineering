s3_bucket_name = "{s3_bucket_name}" # Change this line, enter your S3 bucket name within the quotation marks

s3_bucket_url = f"s3://{s3_bucket_name}"

# department_id, department_name
departments_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/departments").rdd

# category_id, category_department_id, category_name
categories_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/categories").rdd

# product_id, product_category_id, product_name, product_description, product_price, product_image
products_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/products").rdd

# customer_id, customer_fname, customer_lname, customer_email, customer_password, customer_street, customer_city, customer_state, customer_zipcode
customers_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/customers").rdd

# order_id, order_date, order_customer_id, order_status
orders_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/orders").rdd

# order_item_id, order_item_order_id, order_item_product_id, order_item_quantity, order_item_subtotal, order_item_product_price
order_items_rdd = spark.read.parquet(f"{s3_bucket_url}/online_retail_dataset/order_items").rdd

# highest volume product
order_items_product_key = order_items_rdd.map(lambda order_item: (order_item[2], order_item)) # set key to product_id for join
product_key = products_rdd.map(lambda product: (product[0], product)) # set key to product_id for join
order_items_product = order_items_product_key.join(product_key) # join order_items with products

product_volume = order_items_product.map(lambda order_product: (order_product[1][1][2], order_product[1][0][3])) # extract just product name and volume from the dataset

reduced = product_volume.reduceByKey(lambda x, y: x+y) # sum product volume 

sorted = reduced.map(lambda x: (x[1], x[0])).sortByKey(False).map(lambda x: (x[1], x[0])) # flip key/value to sort by key, then switch back

print(sorted.take(5))