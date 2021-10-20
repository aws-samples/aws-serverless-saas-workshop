# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

class Product:
    key =''
    def __init__(self, productId, sku, name, price, category):
        self.productId = productId
        self.sku = sku
        self.name = name
        self.price = price
        self.category = category

class Category:
    def __init__(self, id, name):
        self.id = id
        self.name = name
                

        

               

        
