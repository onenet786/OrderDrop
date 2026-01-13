const validatePagination = (req, res, next) => {
  const page = req.query.page ? parseInt(req.query.page, 10) : 1;
  const pageSize = req.query.pageSize ? parseInt(req.query.pageSize, 10) : 20;

  if (page < 1) {
    return res.status(400).json({
      success: false,
      message: 'Page must be greater than 0'
    });
  }

  if (pageSize < 1 || pageSize > 100) {
    return res.status(400).json({
      success: false,
      message: 'Page size must be between 1 and 100'
    });
  }

  req.pagination = {
    page,
    pageSize,
    offset: (page - 1) * pageSize
  };

  next();
};

const addPaginationToResponse = (data, total, page, pageSize) => {
  return {
    data,
    pagination: {
      page,
      pageSize,
      total,
      pages: Math.ceil(total / pageSize),
      hasNextPage: page < Math.ceil(total / pageSize),
      hasPrevPage: page > 1
    }
  };
};

module.exports = {
  validatePagination,
  addPaginationToResponse
};
