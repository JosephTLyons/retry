pub type MockNetworkSuccessResponse {
  SuccessfulConnection
  ValidData
}

pub type MockNetworkErrorResponse {
  ConnectionTimeout
  ServerUnavailable
  InvalidResponse
}
