/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 */
import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';
import { environment } from 'src/environments/environment';
import { Order } from './models/order.interface';

@Injectable({
  providedIn: 'root',
})
export class OrdersService {
  orders: Order[] = [];
  baseUrl = environment.apiGatewayUrl;
  constructor(private http: HttpClient) {}

  fetch(): Observable<Order[]> {
    return this.http.get<Order[]>(`${this.baseUrl}/orders`);
  }

  get(orderId: string): Observable<Order> {
    const url = `${this.baseUrl}/order/${orderId}`;
    return this.http.get<Order>(url);
  }

  create(order: Order): Observable<Order> {
    return this.http.post<Order>(`${this.baseUrl}/order`, order);
  }
}
