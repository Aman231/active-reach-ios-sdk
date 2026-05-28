import Foundation

/// E-commerce helper for iOS. Parity port of
/// the web SDK source (web SDK ≥1.4.0; back-in-stock
/// waitlist landed 2026-05-24).
///
/// Method names + emitted event names are pinned by
/// the cross-SDK drift contract. Drift on
/// either side breaks canonical_mapper consumers.
///
/// Cart abandonment is server-side
/// (storefront_cart_abandonment_scanner.py). The SDK only emits
/// canonical cart events; the scanner does the 30-min-no-purchase
/// pattern match.
///
/// Usage:
///
///   let ecommerce = EcommerceTracker(aegis: Aegis.shared)
///   ecommerce.productViewed(product)
///   ecommerce.addToCart(product)
///   ecommerce.orderCompleted(order)
public final class EcommerceTracker {

    private let aegis: Aegis

    public init(aegis: Aegis = .shared) {
        self.aegis = aegis
    }

    // MARK: - Product discovery

    public func productViewed(_ product: EcommerceProduct) {
        aegis.track("product_viewed", properties: productProperties(product))
    }

    public func productListViewed(_ list: EcommerceProductList) {
        var props: [String: Any] = ["products": list.products.map(productMap)]
        list.listId.map { props["list_id"] = $0 }
        list.listName.map { props["list_name"] = $0 }
        list.category.map { props["category"] = $0 }
        aegis.track("product_list_viewed", properties: props)
    }

    public func productClicked(
        _ product: EcommerceProduct,
        listId: String? = nil,
        position: Int? = nil,
        section: String? = nil
    ) {
        var props = productProperties(product)
        if let id = listId ?? product.listId { props["list_id"] = id }
        if let p = position ?? product.position { props["position"] = p }
        section.map { props["section"] = $0 }
        aegis.track("product_clicked", properties: props)
    }

    public func productImpressed(
        _ product: EcommerceProduct,
        listId: String? = nil,
        position: Int? = nil,
        section: String? = nil
    ) {
        var props = productProperties(product)
        if let id = listId ?? product.listId { props["list_id"] = id }
        if let p = position ?? product.position { props["position"] = p }
        section.map { props["section"] = $0 }
        aegis.track("product_impression", properties: props)
    }

    public func categoryFiltered(
        category: String,
        previousCategory: String? = nil,
        resultCount: Int? = nil
    ) {
        var props: [String: Any] = ["category": category]
        previousCategory.map { props["previous_category"] = $0 }
        resultCount.map { props["result_count"] = $0 }
        aegis.track("category_filtered", properties: props)
    }

    public func searchPerformed(_ search: EcommerceSearch) {
        var props: [String: Any] = ["query": search.query]
        search.resultsCount.map { props["results_count"] = $0 }
        search.filters.map { props["filters"] = $0 }
        aegis.track("search_performed", properties: props)
    }

    // MARK: - Cart

    public func addToCart(_ product: EcommerceProduct) {
        aegis.track("cart_item_added", properties: productProperties(product))
    }

    public func removeFromCart(_ product: EcommerceProduct) {
        var props: [String: Any] = [
            "product_id": product.productId,
            "sku": product.sku ?? product.productId,
            "name": product.name,
            "price": product.price,
            "quantity": product.quantity,
            "currency": product.currency,
        ]
        product.variantId.map { props["variant_id"] = $0 }
        aegis.track("cart_item_removed", properties: props)
    }

    public func cartViewed(_ cart: EcommerceCart) {
        var props: [String: Any] = [
            "value": cart.value,
            "currency": cart.currency,
            "num_items": cart.products.reduce(0) { $0 + $1.quantity },
            "products": cart.products.map(productMap),
        ]
        cart.cartId.map { props["cart_id"] = $0 }
        aegis.track("cart_viewed", properties: props)
    }

    // MARK: - Checkout

    public func checkoutStarted(_ checkout: EcommerceCheckout) {
        var props: [String: Any] = [
            "value": checkout.value,
            "currency": checkout.currency,
            "num_items": checkout.products.reduce(0) { $0 + $1.quantity },
            "products": checkout.products.map(productMap),
        ]
        checkout.checkoutId.map { props["checkout_id"] = $0 }
        checkout.coupon.map { props["coupon"] = $0 }
        checkout.shipping.map { props["shipping"] = $0 }
        checkout.tax.map { props["tax"] = $0 }
        aegis.track("checkout_started", properties: props)
    }

    public func checkoutStep(_ step: Int, properties: [String: Any]? = nil) {
        var props: [String: Any] = ["step": step]
        if let extra = properties { props.merge(extra, uniquingKeysWith: { _, b in b }) }
        aegis.track("checkout_step", properties: props)
    }

    // MARK: - Order

    public func orderCompleted(_ order: EcommerceOrder) {
        var props: [String: Any] = [
            "order_id": order.orderId,
            "value": order.value,
            "revenue": order.revenue ?? order.value,
            "currency": order.currency,
            "num_items": order.products.reduce(0) { $0 + $1.quantity },
            "products": order.products.map(productMap),
        ]
        order.coupon.map { props["coupon"] = $0 }
        order.shipping.map { props["shipping"] = $0 }
        order.tax.map { props["tax"] = $0 }
        order.discount.map { props["discount"] = $0 }
        order.paymentMethod.map { props["payment_method"] = $0 }
        aegis.track("order_completed", properties: props)
    }

    public func orderRefunded(orderId: String, value: Double? = nil, products: [EcommerceProduct]? = nil) {
        var props: [String: Any] = ["order_id": orderId]
        value.map { props["value"] = $0 }
        products.map { props["products"] = $0.map(productMap) }
        aegis.track("order_refunded", properties: props)
    }

    // MARK: - Coupons

    public func couponApplied(_ coupon: EcommerceCoupon) {
        aegis.track("coupon_applied", properties: couponProperties(coupon))
    }

    public func couponRemoved(_ coupon: EcommerceCoupon) {
        aegis.track("coupon_removed", properties: couponProperties(coupon))
    }

    // MARK: - Wishlist

    public func wishlistItemAdded(_ wishlist: EcommerceWishlist) {
        var props: [String: Any] = [
            "product_id": wishlist.product.productId,
            "sku": wishlist.product.sku ?? wishlist.product.productId,
            "name": wishlist.product.name,
            "price": wishlist.product.price,
        ]
        wishlist.wishlistId.map { props["wishlist_id"] = $0 }
        wishlist.wishlistName.map { props["wishlist_name"] = $0 }
        wishlist.product.variantId.map { props["variant_id"] = $0 }
        aegis.track("wishlist_item_added", properties: props)
    }

    // MARK: - Back-in-stock waitlist
    //
    // Server-side substrate: contact_events keyed on
    // (organization_id, contact_id, event_name='product_waitlisted',
    //  event_properties['product_id']). Resolved by
    // product_event_trigger_service._get_waitlisted_contacts and fans
    // out the catalog.back_in_stock journey trigger when
    // stock_event_handler_worker detects the SKU flipping back into
    // stock. Without this event, the BIS bridge is dead code.
    public func productWaitlisted(_ waitlist: EcommerceWaitlist) {
        var props: [String: Any] = [
            "product_id": waitlist.product.productId,
            "sku": waitlist.product.sku ?? waitlist.product.productId,
            "name": waitlist.product.name,
            "price": waitlist.product.price,
        ]
        waitlist.product.variantId.map { props["variant_id"] = $0 }
        waitlist.channels.map { props["channels"] = $0.map(\.rawValue) }
        aegis.track("product_waitlisted", properties: props)
    }

    // MARK: - Promotions

    public func promotionViewed(_ promo: EcommercePromotion) {
        aegis.track("promotion_viewed", properties: promotionProperties(promo))
    }

    public func promotionClicked(_ promo: EcommercePromotion) {
        aegis.track("promotion_clicked", properties: promotionProperties(promo))
    }

    // MARK: - Helpers

    private func productProperties(_ p: EcommerceProduct) -> [String: Any] {
        var props: [String: Any] = [
            "product_id": p.productId,
            "sku": p.sku ?? p.productId,
            "name": p.name,
            "price": p.price,
            "quantity": p.quantity,
            "currency": p.currency,
        ]
        p.category.map { props["category"] = $0 }
        p.brand.map { props["brand"] = $0 }
        p.variantId.map { props["variant_id"] = $0 }
        p.variantLabel.map { props["variant_label"] = $0 }
        p.imageUrl.map { props["image_url"] = $0 }
        p.url.map { props["url"] = $0 }
        p.position.map { props["position"] = $0 }
        return props
    }

    private func productMap(_ p: EcommerceProduct) -> [String: Any] {
        var m: [String: Any] = [
            "product_id": p.productId,
            "sku": p.sku ?? p.productId,
            "name": p.name,
            "price": p.price,
            "quantity": p.quantity,
            "currency": p.currency,
        ]
        p.category.map { m["category"] = $0 }
        p.brand.map { m["brand"] = $0 }
        p.variantId.map { m["variant_id"] = $0 }
        p.variantLabel.map { m["variant_label"] = $0 }
        p.position.map { m["position"] = $0 }
        return m
    }

    private func couponProperties(_ c: EcommerceCoupon) -> [String: Any] {
        var props: [String: Any] = ["coupon_code": c.couponCode]
        c.couponId.map { props["coupon_id"] = $0 }
        c.discountValue.map { props["discount_value"] = $0 }
        c.discountType.map { props["discount_type"] = $0.rawValue }
        c.orderId.map { props["order_id"] = $0 }
        c.cartId.map { props["cart_id"] = $0 }
        return props
    }

    private func promotionProperties(_ p: EcommercePromotion) -> [String: Any] {
        var props: [String: Any] = ["name": p.name]
        p.promotionId.map { props["promotion_id"] = $0 }
        p.creative.map { props["creative"] = $0 }
        p.position.map { props["position"] = $0 }
        return props
    }
}
