# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

class Order:
    key=''
    def __init__(self, orderId, orderName, orderProducts):
        self.orderId = orderId
        self.orderName = orderName
        self.orderProducts = orderProducts

class  OrderProduct:

    def __init__(self, productId, price, quantity):
        self.productId = productId
        self.price = price
        self.quantity = quantity



