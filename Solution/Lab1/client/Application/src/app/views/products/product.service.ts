/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 */
import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';
import { environment } from 'src/environments/environment';
import { Product } from './models/product.interface';

@Injectable({
  providedIn: 'root',
})
export class ProductService {
  constructor(private http: HttpClient) {}
  baseUrl = environment.apiGatewayUrl;

  fetch(): Observable<Product[]> {
    return this.http.get<Product[]>(`${this.baseUrl}/products`);
  }

  get(productId: string): Observable<Product> {
    const url = `${this.baseUrl}/product/${productId}`;
    return this.http.get<Product>(url);
  }

  delete(product: Product) {
    const url = `${this.baseUrl}/product/${product.productId}`;
    return this.http.delete<Product>(url);
  }

  patch(product: Product) {
    const url = `${this.baseUrl}/product/${product.productId}`;
    return this.http.patch<Product>(url, product);
  }

  post(product: Product) {
    return this.http.post<Product>(`${this.baseUrl}/product`, product);
  }
}
