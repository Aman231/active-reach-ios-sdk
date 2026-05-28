import Foundation

/// E-commerce type contracts. Wire-shape parity with
/// the web SDK source. Currency defaults to "INR"
/// (Aegis is India-first); quantity defaults to 1.

public enum CouponDiscountType: String {
    case percentage
    case fixed
}

public enum WaitlistChannel: String {
    case whatsapp
    case sms
    case email
    case push
}

public struct EcommerceProduct {
    public let productId: String
    public let name: String
    public let price: Double
    public let sku: String?
    public let quantity: Int
    public let currency: String
    public let category: String?
    public let brand: String?
    public let variantId: String?
    public let variantLabel: String?
    public let imageUrl: String?
    public let url: String?
    public let position: Int?
    public let listId: String?

    public init(
        productId: String,
        name: String,
        price: Double,
        sku: String? = nil,
        quantity: Int = 1,
        currency: String = "INR",
        category: String? = nil,
        brand: String? = nil,
        variantId: String? = nil,
        variantLabel: String? = nil,
        imageUrl: String? = nil,
        url: String? = nil,
        position: Int? = nil,
        listId: String? = nil
    ) {
        self.productId = productId
        self.name = name
        self.price = price
        self.sku = sku
        self.quantity = quantity
        self.currency = currency
        self.category = category
        self.brand = brand
        self.variantId = variantId
        self.variantLabel = variantLabel
        self.imageUrl = imageUrl
        self.url = url
        self.position = position
        self.listId = listId
    }
}

public struct EcommerceCart {
    public let value: Double
    public let products: [EcommerceProduct]
    public let cartId: String?
    public let currency: String

    public init(value: Double, products: [EcommerceProduct], cartId: String? = nil, currency: String = "INR") {
        self.value = value
        self.products = products
        self.cartId = cartId
        self.currency = currency
    }
}

public struct EcommerceCheckout {
    public let value: Double
    public let products: [EcommerceProduct]
    public let checkoutId: String?
    public let currency: String
    public let coupon: String?
    public let shipping: Double?
    public let tax: Double?

    public init(
        value: Double,
        products: [EcommerceProduct],
        checkoutId: String? = nil,
        currency: String = "INR",
        coupon: String? = nil,
        shipping: Double? = nil,
        tax: Double? = nil
    ) {
        self.value = value
        self.products = products
        self.checkoutId = checkoutId
        self.currency = currency
        self.coupon = coupon
        self.shipping = shipping
        self.tax = tax
    }
}

public struct EcommerceOrder {
    public let orderId: String
    public let value: Double
    public let products: [EcommerceProduct]
    public let revenue: Double?
    public let currency: String
    public let coupon: String?
    public let shipping: Double?
    public let tax: Double?
    public let discount: Double?
    public let paymentMethod: String?

    public init(
        orderId: String,
        value: Double,
        products: [EcommerceProduct],
        revenue: Double? = nil,
        currency: String = "INR",
        coupon: String? = nil,
        shipping: Double? = nil,
        tax: Double? = nil,
        discount: Double? = nil,
        paymentMethod: String? = nil
    ) {
        self.orderId = orderId
        self.value = value
        self.products = products
        self.revenue = revenue
        self.currency = currency
        self.coupon = coupon
        self.shipping = shipping
        self.tax = tax
        self.discount = discount
        self.paymentMethod = paymentMethod
    }
}

public struct EcommerceCoupon {
    public let couponCode: String
    public let couponId: String?
    public let discountValue: Double?
    public let discountType: CouponDiscountType?
    public let orderId: String?
    public let cartId: String?

    public init(
        couponCode: String,
        couponId: String? = nil,
        discountValue: Double? = nil,
        discountType: CouponDiscountType? = nil,
        orderId: String? = nil,
        cartId: String? = nil
    ) {
        self.couponCode = couponCode
        self.couponId = couponId
        self.discountValue = discountValue
        self.discountType = discountType
        self.orderId = orderId
        self.cartId = cartId
    }
}

public struct EcommerceSearch {
    public let query: String
    public let resultsCount: Int?
    public let filters: [String: Any]?

    public init(query: String, resultsCount: Int? = nil, filters: [String: Any]? = nil) {
        self.query = query
        self.resultsCount = resultsCount
        self.filters = filters
    }
}

public struct EcommerceProductList {
    public let products: [EcommerceProduct]
    public let listId: String?
    public let listName: String?
    public let category: String?

    public init(products: [EcommerceProduct], listId: String? = nil, listName: String? = nil, category: String? = nil) {
        self.products = products
        self.listId = listId
        self.listName = listName
        self.category = category
    }
}

public struct EcommerceWishlist {
    public let product: EcommerceProduct
    public let wishlistId: String?
    public let wishlistName: String?

    public init(product: EcommerceProduct, wishlistId: String? = nil, wishlistName: String? = nil) {
        self.product = product
        self.wishlistId = wishlistId
        self.wishlistName = wishlistName
    }
}

public struct EcommerceWaitlist {
    public let product: EcommerceProduct
    public let channels: [WaitlistChannel]?

    public init(product: EcommerceProduct, channels: [WaitlistChannel]? = nil) {
        self.product = product
        self.channels = channels
    }
}

public struct EcommercePromotion {
    public let name: String
    public let promotionId: String?
    public let creative: String?
    public let position: String?

    public init(name: String, promotionId: String? = nil, creative: String? = nil, position: String? = nil) {
        self.name = name
        self.promotionId = promotionId
        self.creative = creative
        self.position = position
    }
}
